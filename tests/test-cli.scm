(import (scheme base) (scheme write) (kaappi cli))

(define pass 0)
(define fail 0)

(define (check name expected actual)
  (if (equal? expected actual)
      (begin (set! pass (+ pass 1))
             (display "  PASS: ") (display name) (newline))
      (begin (set! fail (+ fail 1))
             (display "  FAIL: ") (display name) (newline)
             (display "    expected: ") (write expected) (newline)
             (display "    got:      ") (write actual) (newline))))

(define app
  (cli "myapp" "A test application"
    (flag "-v" "--verbose" "Verbose output")
    (option "-n" "--count" "Number of items" 10)
    (option "-o" "--output" "Output file" "out.txt")
    (argument "input" "Input file")
    (command "init" "Initialize a project"
      (argument "name" "Project name"))
    (command "build" "Build the project"
      (option "-j" "--jobs" "Parallel jobs" 4))))

(define (capture-output thunk)
  (let ((port (open-output-string)))
    (parameterize ((current-output-port port))
      (thunk))
    (get-output-string port)))

(define (string-contains? s sub)
  (let ((sl (string-length s)) (subl (string-length sub)))
    (let loop ((i 0))
      (cond ((> (+ i subl) sl) #f)
            ((string=? (substring s i (+ i subl)) sub) #t)
            (else (loop (+ i 1)))))))

(define last-call #f)

(define test-handlers
  `(("init" . ,(lambda (r)
                 ;; car of the sub-parse's positional args — the access
                 ;; pattern that crashed on `myapp init --help` before
                 ;; per-subcommand help was routed around the handlers
                 (set! last-call
                   (cons "init" (cdr (car (parsed-args (parsed-sub r))))))))
    ("build" . ,(lambda (r)
                  (set! last-call
                    (cons "build" (parsed-ref (parsed-sub r) "jobs")))))
    (#f . ,(lambda (r) (set! last-call 'default)))))

(define (dispatch argv)
  (set! last-call #f)
  (capture-output (lambda () (run-cli app test-handlers argv))))

;; --- Options ---
(display "=== Options ===") (newline)

(let ((r (run-cli-parse app '())))
  (check "default count" 10 (parsed-ref r "count"))
  (check "default output" "out.txt" (parsed-ref r "output"))
  (check "default verbose" #f (parsed-ref r "verbose")))

(let ((r (run-cli-parse app '("-v"))))
  (check "verbose flag" #t (parsed-flag? r "verbose")))

(let ((r (run-cli-parse app '("--verbose"))))
  (check "verbose long" #t (parsed-flag? r "verbose")))

(let ((r (run-cli-parse app '("-n" "42"))))
  (check "count short" 42 (parsed-ref r "count")))

(let ((r (run-cli-parse app '("--count" "5"))))
  (check "count long" 5 (parsed-ref r "count")))

(let ((r (run-cli-parse app '("--count=99"))))
  (check "count=value" 99 (parsed-ref r "count")))

(let ((r (run-cli-parse app '("-v" "-n" "3" "-o" "result.json"))))
  (check "multi verbose" #t (parsed-flag? r "verbose"))
  (check "multi count" 3 (parsed-ref r "count"))
  (check "multi output" "result.json" (parsed-ref r "output")))

;; Flag with =value: the value part is ignored, the flag is set to #t
(let ((r (run-cli-parse app '("--verbose=true"))))
  (check "flag =true sets flag" #t (parsed-flag? r "verbose")))

(let ((r (run-cli-parse app '("--verbose=false"))))
  (check "flag =false sets flag" #t (parsed-flag? r "verbose")))

(let ((r (run-cli-parse app '("--verbose="))))
  (check "flag =empty sets flag" #t (parsed-flag? r "verbose")))

;; Option values never consume option-shaped tokens
(let ((r (run-cli-parse app '("-n" "-v"))))
  (check "-n does not eat -v" 10 (parsed-ref r "count"))
  (check "-n -v sets verbose" #t (parsed-flag? r "verbose")))

(let ((r (run-cli-parse app '("-n" "--help"))))
  (check "-n does not eat --help" #t (parsed-ref r "help"))
  (check "-n --help keeps count default" 10 (parsed-ref r "count")))

(let ((r (run-cli-parse app '("-n" "--"))))
  (check "-n does not eat --" 10 (parsed-ref r "count")))

;; A short flag whose letter spells a Scheme number ("-i" parses as the
;; complex -i) must not be consumed as a value either
(define iapp
  (cli "iapp" "I"
    (flag "-i" "--interactive" "Interactive")
    (option "-n" "--count" "Number" 10)))

(let ((r (run-cli-parse iapp '("-n" "-i"))))
  (check "-n does not eat number-shaped flag -i" 10 (parsed-ref r "count"))
  (check "-n -i sets interactive" #t (parsed-flag? r "interactive")))

;; Negative numbers and the lone "-" are still valid values
(let ((r (run-cli-parse app '("-n" "-5"))))
  (check "-n takes negative number" -5 (parsed-ref r "count")))

(let ((r (run-cli-parse app '("-o" "-"))))
  (check "-o takes lone dash" "-" (parsed-ref r "output")))

;; Coercion pins: non-numeric input keeps the raw string; full Scheme
;; number syntax is accepted via string->number
(let ((r (run-cli-parse app '("--count=abc"))))
  (check "non-numeric value kept as string" "abc" (parsed-ref r "count")))

(let ((r (run-cli-parse app '("--count=1e3"))))
  (check "scientific notation coerces" 1000.0 (parsed-ref r "count")))

(let ((r (run-cli-parse app '("--count=1/2"))))
  (check "rational syntax coerces" 1/2 (parsed-ref r "count")))

;; --- Arguments ---
(display "=== Arguments ===") (newline)

(let ((r (run-cli-parse app '("myfile.txt"))))
  (let ((args (parsed-args r)))
    (check "positional" "myfile.txt"
      (if (pair? args) (cdar args) #f))))

(let ((r (run-cli-parse app '("-v" "data.csv"))))
  (let ((args (parsed-args r)))
    (check "arg after flag" "data.csv"
      (if (pair? args) (cdar args) #f))))

;; --- Subcommands ---
(display "=== Commands ===") (newline)

(let ((r (run-cli-parse app '("init" "my-project"))))
  (check "command name" "init" (parsed-command r))
  (check "command arg" "my-project"
    (let ((sub (parsed-sub r)))
      (if sub (cdr (car (parsed-args sub))) #f))))

(let ((r (run-cli-parse app '("build" "-j" "8"))))
  (check "command build" "build" (parsed-command r))
  (check "command opt" 8
    (let ((sub (parsed-sub r)))
      (if sub (parsed-ref sub "jobs") #f))))

;; --- Help ---
(display "=== Help ===") (newline)

(let ((r (run-cli-parse app '("--help"))))
  (check "help flag" #t (parsed-ref r "help")))

(let ((r (run-cli-parse app '("-h"))))
  (check "help short" #t (parsed-ref r "help")))

;; --- Subcommand help ---
(display "=== Subcommand Help ===") (newline)

(let ((r (run-cli-parse app '("build" "--help"))))
  (check "sub help flag in sub parse" #t
    (let ((sub (parsed-sub r)))
      (if sub (parsed-ref sub "help") #f))))

(let ((r (run-cli-parse app '("init" "-h"))))
  (check "sub help short in sub parse" #t
    (let ((sub (parsed-sub r)))
      (if sub (parsed-ref sub "help") #f))))

(let ((out (dispatch '("build" "--help"))))
  (check "build --help skips handler" #f last-call)
  (check "build --help prints sub help" #t
    (string-contains? out "myapp build — Build the project"))
  (check "build --help prints sub usage" #t
    (string-contains? out "Usage: myapp build")))

(let ((out (dispatch '("init" "--help"))))
  (check "init --help skips handler" #f last-call)
  (check "init --help prints sub help" #t
    (string-contains? out "myapp init — Initialize a project")))

(let ((out (dispatch '("build" "-h"))))
  (check "build -h skips handler" #f last-call)
  (check "build -h prints sub usage" #t
    (string-contains? out "Usage: myapp build")))

(let ((out (dispatch '("--help"))))
  (check "top-level --help skips handlers" #f last-call)
  (check "top-level --help prints app help" #t
    (string-contains? out "myapp — A test application")))

(begin
  (dispatch '("init" "proj"))
  (check "init handler still runs" '("init" . "proj") last-call))

(begin
  (dispatch '("build" "-j" "2"))
  (check "build handler still runs" '("build" . 2) last-call))

(begin
  (dispatch '("input.txt"))
  (check "default handler still runs" 'default last-call))

;; --- Generated help output ---
(display "=== Help Output ===") (newline)
(generate-help app)
(newline)
(display "=== Subcommand Help ===") (newline)
(generate-help app "build")

(newline)
(display "=== Results: ")
(display pass) (display " passed, ")
(display fail) (display " failed ===")
(newline)
(when (> fail 0) (exit 1))
