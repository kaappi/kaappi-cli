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
