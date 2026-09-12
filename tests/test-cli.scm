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
(define last-errors #f)

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
    (#f . ,(lambda (r) (set! last-call 'default)))
    ;; usage errors: record them instead of the default print-and-exit
    (error . ,(lambda (r) (set! last-errors (parsed-errors r))))))

(define (dispatch argv)
  (set! last-call #f)
  (set! last-errors #f)
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
  (check "-n -v sets verbose" #t (parsed-flag? r "verbose"))
  (check "-n -v reports the missing value"
    '("option '-n' requires a value") (parsed-errors r)))

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

;; --- Errors ---
(display "=== Errors ===") (newline)

(let ((r (run-cli-parse app '("-v" "-n" "3" "f.txt"))))
  (check "clean parse has no errors" '() (parsed-errors r)))

(let ((r (run-cli-parse app '("--bogus"))))
  (check "unknown long option" '("unknown option '--bogus'") (parsed-errors r)))

(let ((r (run-cli-parse app '("--bogus=5"))))
  (check "unknown long option with =value" '("unknown option '--bogus'")
    (parsed-errors r)))

(let ((r (run-cli-parse app '("-z"))))
  (check "unknown short option" '("unknown option '-z'") (parsed-errors r)))

(let ((r (run-cli-parse app '("-z" "-v" "f.txt"))))
  (check "parsing continues after an unknown option" #t (parsed-flag? r "verbose"))
  (check "positional after an unknown option" "f.txt" (cdar (parsed-args r)))
  (check "only the unknown option is reported" '("unknown option '-z'")
    (parsed-errors r)))

(let ((r (run-cli-parse app '("-z" "--bogus"))))
  (check "errors keep argv order"
    '("unknown option '-z'" "unknown option '--bogus'") (parsed-errors r)))

(let ((r (run-cli-parse app '("-n"))))
  (check "missing value at end of argv" '("option '-n' requires a value")
    (parsed-errors r))
  (check "missing value keeps the default" 10 (parsed-ref r "count")))

(let ((r (run-cli-parse app '("--count" "-v"))))
  (check "long option missing value names the long form"
    '("option '--count' requires a value") (parsed-errors r)))

(let ((r (run-cli-parse app '("a.txt" "b.txt"))))
  (check "extra positional" '("unexpected argument 'b.txt'") (parsed-errors r))
  (check "declared positional still bound" "a.txt" (cdar (parsed-args r))))

;; app has a positional, so a mistyped command fills it and the rest is extra
(let ((r (run-cli-parse app '("inti" "proj"))))
  (check "mistyped command with positionals declared"
    '("unexpected argument 'proj'") (parsed-errors r)))

;; commands-only app: a bare word can only be an unknown command
(define capp
  (cli "capp" "Commands only"
    (flag "-v" "--verbose" "Verbose")
    (command "init" "Initialize" (argument "name" "Name"))))

(let ((r (run-cli-parse capp '("inti" "proj"))))
  (check "unknown command" '("unknown command 'inti'") (parsed-errors r))
  (check "unknown command is not a command" #f (parsed-command r))
  (check "unknown command's arguments are not reported twice"
    '() (parsed-args r)))

(let ((r (run-cli-parse capp '("-v" "inti"))))
  (check "options before an unknown command still parse" #t
    (parsed-flag? r "verbose")))

;; subcommand errors surface at the top level and in the sub result
(let ((r (run-cli-parse app '("build" "--bogus"))))
  (check "sub error at top level" '("unknown option '--bogus'") (parsed-errors r))
  (check "sub error in sub result" '("unknown option '--bogus'")
    (parsed-errors (parsed-sub r))))

(let ((r (run-cli-parse app '("build" "-j"))))
  (check "sub option missing value" '("option '-j' requires a value")
    (parsed-errors r)))

(let ((r (run-cli-parse app '("init" "a" "b"))))
  (check "sub extra positional" '("unexpected argument 'b'") (parsed-errors r)))

(let ((r (run-cli-parse app '("-z" "build" "-j"))))
  (check "top-level errors precede sub errors"
    '("unknown option '-z'" "option '-j' requires a value") (parsed-errors r)))

;; help wins over errors
(let ((r (run-cli-parse app '("--bogus" "--help"))))
  (check "help after an error still wins" #t (parsed-ref r "help"))
  (check "help result carries no errors" '() (parsed-errors r)))

(let ((r (run-cli-parse app '("--help=5"))))
  (check "--help=value is help" #t (parsed-ref r "help")))

;; --- End of options ---
(display "=== End of options ===") (newline)

(let ((r (run-cli-parse app '("--" "-v"))))
  (check "-- makes -v data" "-v" (cdar (parsed-args r)))
  (check "-- keeps verbose unset" #f (parsed-flag? r "verbose"))
  (check "-- itself is not an error" '() (parsed-errors r)))

(let ((r (run-cli-parse app '("-v" "--" "--verbose"))))
  (check "options before -- still parse" #t (parsed-flag? r "verbose"))
  (check "long option after -- is data" "--verbose" (cdar (parsed-args r))))

(let ((r (run-cli-parse app '("--" "init"))))
  (check "command name after -- is data" #f (parsed-command r))
  (check "command name after -- binds positional" "init" (cdar (parsed-args r))))

(let ((r (run-cli-parse app '("--" "--"))))
  (check "second -- is data" "--" (cdar (parsed-args r))))

(let ((r (run-cli-parse app '("init" "--" "-x"))))
  (check "-- after a command reaches the subcommand" "-x"
    (cdar (parsed-args (parsed-sub r))))
  (check "-- after a command is clean" '() (parsed-errors r)))

(let ((r (run-cli-parse app '("-5"))))
  (check "negative number positional" "-5" (cdar (parsed-args r)))
  (check "negative number is not an unknown option" '() (parsed-errors r)))

(let ((r (run-cli-parse app '("-"))))
  (check "lone dash positional" "-" (cdar (parsed-args r))))

;; --- Top-level options after the command ---
(display "=== Options after command ===") (newline)

(let ((r (run-cli-parse app '("init" "-n" "5" "x"))))
  (check "top-level option after command" 5 (parsed-ref r "count"))
  (check "its value does not shift sub positionals" "x"
    (cdar (parsed-args (parsed-sub r))))
  (check "option after command is clean" '() (parsed-errors r)))

(let ((r (run-cli-parse app '("init" "x" "-n" "5"))))
  (check "top-level option after sub positional" 5 (parsed-ref r "count"))
  (check "sub positional before option" "x" (cdar (parsed-args (parsed-sub r)))))

(let ((r (run-cli-parse app '("init" "-v" "x"))))
  (check "top-level flag after command" #t (parsed-flag? r "verbose")))

(let ((r (run-cli-parse app '("init" "--count=7" "x"))))
  (check "top-level --opt=value after command" 7 (parsed-ref r "count")))

(let ((r (run-cli-parse app '("init" "-o" "out" "x"))))
  (check "top-level string option after command" "out" (parsed-ref r "output"))
  (check "string option value not taken as sub positional" "x"
    (cdar (parsed-args (parsed-sub r)))))

(let ((r (run-cli-parse app '("build" "-j" "8" "-n" "5"))))
  (check "sub option and top-level option mixed: sub" 8
    (parsed-ref (parsed-sub r) "jobs"))
  (check "sub option and top-level option mixed: top" 5 (parsed-ref r "count")))

;; the subcommand's own option wins after its token
(define sapp
  (cli "sapp" "Shadowed option"
    (option "-j" "--jobs" "Top-level jobs" 1)
    (command "build" "Build"
      (option "-j" "--jobs" "Build jobs" 4))))

(let ((r (run-cli-parse sapp '("build" "-j" "8"))))
  (check "shadowed option goes to sub" 8 (parsed-ref (parsed-sub r) "jobs"))
  (check "shadowed option leaves top default" 1 (parsed-ref r "jobs")))

(let ((r (run-cli-parse sapp '("-j" "2" "build" "-j" "8"))))
  (check "shadowed option before command is top" 2 (parsed-ref r "jobs"))
  (check "shadowed option after command is sub" 8
    (parsed-ref (parsed-sub r) "jobs")))

;; --- run-cli error dispatch ---
(display "=== run-cli errors ===") (newline)

(let ((out (dispatch '("--bogus"))))
  (check "usage error skips handlers" #f last-call)
  (check "usage error reaches the error handler"
    '("unknown option '--bogus'") last-errors)
  (check "error handler suppresses default output" "" out))

(begin
  (dispatch '("build" "-j"))
  (check "sub usage error skips the sub handler" #f last-call)
  (check "sub usage error reaches the error handler"
    '("option '-j' requires a value") last-errors))

(begin
  (dispatch '("inti" "proj"))
  (check "extra positional skips the default handler" #f last-call)
  (check "extra positional reaches the error handler"
    '("unexpected argument 'proj'") last-errors))

(let ((out (dispatch '("--bogus" "--help"))))
  (check "--help beside an error prints help" #t
    (string-contains? out "myapp — A test application"))
  (check "--help beside an error is not an error" #f last-errors))

(begin
  (dispatch '("-n" "3" "f.txt"))
  (check "clean argv still dispatches" 'default last-call)
  (check "clean argv has no errors" #f last-errors))

;; no #f handler and no command given: a usage error, not silent help
(let ((cmd-only `(("init" . ,(lambda (r) (set! last-call 'init)))
                  (error . ,(lambda (r) (set! last-errors (parsed-errors r)))))))
  (set! last-call #f) (set! last-errors #f)
  (capture-output (lambda () (run-cli app cmd-only '())))
  (check "missing command is a usage error" '("missing command") last-errors)
  (check "missing command runs no handler" #f last-call))

;; a declared command with no handler entry is the app's bug: it raises
(check "missing handler raises" 'raised
  (guard (e (#t 'raised))
    (capture-output
      (lambda () (run-cli app `(("build" . ,(lambda (r) #f))) '("init" "x"))))
    'returned))

;; no commands and no #f handler: also the app's bug
(check "no default handler raises" 'raised
  (guard (e (#t 'raised))
    (capture-output
      (lambda () (run-cli iapp '() '("-i"))))
    'returned))

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
