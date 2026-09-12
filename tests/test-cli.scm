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

;; option-shaped tokens after an unknown command are still checked;
;; bare words are taken as its arguments and skipped
(let ((r (run-cli-parse capp '("inti" "--bogus"))))
  (check "unknown option after an unknown command is reported"
    '("unknown command 'inti'" "unknown option '--bogus'") (parsed-errors r)))

(let ((r (run-cli-parse capp '("inti" "proj" "-v"))))
  (check "flag after an unknown command still parses" #t
    (parsed-flag? r "verbose"))
  (check "bare words after an unknown command are not reported"
    '("unknown command 'inti'") (parsed-errors r)))

(let ((r (run-cli-parse capp '("inti" "init" "x"))))
  (check "a real command after an unknown command is not dispatched"
    #f (parsed-command r)))

(let ((r (run-cli-parse capp '("inti" "--" "-v"))))
  (check "-- after an unknown command hides the rest" #f
    (parsed-flag? r "verbose")))

;; a dash-leading token whose first letter is no option is an unknown
;; option, not positional data
(let ((r (run-cli-parse app '("-foo"))))
  (check "unknown cluster is reported whole" '("unknown option '-foo'")
    (parsed-errors r))
  (check "unknown cluster is not positional data" #f (cdar (parsed-args r))))

;; a rejected option value that is itself a bad cluster is reported twice:
;; once for the option left without a value, once for the token
(let ((r (run-cli-parse app '("-o" "-foo"))))
  (check "rejected value cluster"
    '("option '-o' requires a value" "unknown option '-foo'")
    (parsed-errors r)))

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

;; --- Short option clusters ---
(display "=== Short option clusters ===") (newline)

(let ((r (run-cli-parse app '("-vv"))))
  (check "repeated flag" #t (parsed-flag? r "verbose"))
  (check "repeated flag is not positional" #f (cdar (parsed-args r)))
  (check "repeated flag is clean" '() (parsed-errors r)))

(let ((r (run-cli-parse app '("-vn" "3"))))
  (check "flag then option: flag" #t (parsed-flag? r "verbose"))
  (check "flag then option takes next token" 3 (parsed-ref r "count")))

(let ((r (run-cli-parse app '("-n5"))))
  (check "attached value" 5 (parsed-ref r "count")))

(let ((r (run-cli-parse app '("-n=5"))))
  (check "attached value with =" 5 (parsed-ref r "count")))

(let ((r (run-cli-parse app '("-vn5" "f.txt"))))
  (check "flag with attached value: flag" #t (parsed-flag? r "verbose"))
  (check "flag with attached value: value" 5 (parsed-ref r "count"))
  (check "positional after cluster" "f.txt" (cdar (parsed-args r))))

(let ((r (run-cli-parse app '("-n-5"))))
  (check "attached negative value" -5 (parsed-ref r "count")))

(let ((r (run-cli-parse app '("-nv"))))
  (check "value option swallows the rest of the token" "v"
    (parsed-ref r "count"))
  (check "swallowed letter is not a flag" #f (parsed-flag? r "verbose")))

(let ((r (run-cli-parse app '("-ores.txt"))))
  (check "attached string value" "res.txt" (parsed-ref r "output")))

;; attached values are taken verbatim: only the first = splits, and an
;; option-shaped value is not second-guessed
(let ((r (run-cli-parse app '("-o=a=b"))))
  (check "attached value keeps later =" "a=b" (parsed-ref r "output")))

(let ((r (run-cli-parse app '("-o-v"))))
  (check "attached option-shaped value is verbatim" "-v" (parsed-ref r "output"))
  (check "attached option-shaped value is not a flag" #f (parsed-flag? r "verbose"))
  (check "attached option-shaped value is clean" '() (parsed-errors r)))

(let ((r (run-cli-parse app '("-vn"))))
  (check "cluster ending in a value option needs a value"
    '("option '-n' requires a value") (parsed-errors r))
  (check "cluster flag still set when value is missing" #t
    (parsed-flag? r "verbose")))

(let ((r (run-cli-parse app '("-vh"))))
  (check "-h inside a cluster is help" #t (parsed-ref r "help")))

(let ((r (run-cli-parse app '("-vz"))))
  (check "unknown letter after a known one" '("unknown option '-z'")
    (parsed-errors r))
  (check "known letters before an unknown one still apply" #t
    (parsed-flag? r "verbose")))

(let ((r (run-cli-parse app '("-1.5e2"))))
  (check "negative real is still data, not a cluster" "-1.5e2"
    (cdar (parsed-args r))))

(let ((r (run-cli-parse app '("--" "-vn5"))))
  (check "cluster after -- is data" "-vn5" (cdar (parsed-args r))))

;; clusters around the command token
(let ((r (run-cli-parse app '("build" "-j8"))))
  (check "sub option attached value" 8 (parsed-ref (parsed-sub r) "jobs")))

(let ((r (run-cli-parse app '("init" "-vn5" "x"))))
  (check "top-level cluster after command: flag" #t (parsed-flag? r "verbose"))
  (check "top-level cluster after command: value" 5 (parsed-ref r "count"))
  (check "top-level cluster after command: sub positional" "x"
    (cdar (parsed-args (parsed-sub r)))))

(let ((r (run-cli-parse sapp '("build" "-j8"))))
  (check "shadowed attached value goes to sub" 8
    (parsed-ref (parsed-sub r) "jobs"))
  (check "shadowed attached value leaves top default" 1 (parsed-ref r "jobs")))

(let ((r (run-cli-parse sapp '("-j2" "build"))))
  (check "attached value before command is top" 2 (parsed-ref r "jobs")))

;; --- Help row on every page ---
(display "=== Help row ===") (newline)

;; init declares no options, but -h still works there, so the page says so
(let ((out (capture-output (lambda () (generate-help app "init")))))
  (check "option-less subcommand shows Options" #t
    (string-contains? out "Options:"))
  (check "option-less subcommand shows the help row" #t
    (string-contains? out "  -h, --help                Show this help"))
  (check "option-less subcommand usage mentions options" #t
    (string-contains? out "Usage: myapp init [options] <name>")))

(define napp
  (cli "napp" "No options at all"
    (argument "file" "Input file")))

(let ((out (capture-output (lambda () (generate-help napp)))))
  (check "option-less app shows the help row" #t
    (string-contains? out "  -h, --help                Show this help"))
  (check "option-less app usage mentions options" #t
    (string-contains? out "Usage: napp [options] <file>")))

(let ((r (run-cli-parse napp '("-h"))))
  (check "option-less app still honours -h" #t (parsed-ref r "help")))

;; --- Reserved help names ---
(display "=== Reserved names ===") (newline)

(define (spec-error thunk)
  (guard (e ((error-object? e) (error-object-message e)))
    (thunk)
    #f))

(check "flag --help is rejected"
  "flag: -h and --help are reserved for the built-in help"
  (spec-error (lambda () (flag "-H" "--help" "Detail"))))

(check "option --help is rejected"
  "option: -h and --help are reserved for the built-in help"
  (spec-error (lambda () (option "-H" "--help" "Detail level" 2))))

(check "flag -h is rejected"
  "flag: -h and --help are reserved for the built-in help"
  (spec-error (lambda () (flag "-h" "--host" "Host"))))

(check "option -h is rejected"
  "option: -h and --help are reserved for the built-in help"
  (spec-error (lambda () (option "-h" "--host" "Host" "localhost"))))

;; the reservation covers both slots, whichever spelling lands in them
(check "-h in the long slot is rejected"
  "flag: -h and --help are reserved for the built-in help"
  (spec-error (lambda () (flag "-H" "-h" "H"))))

(check "--help in the short slot is rejected"
  "flag: -h and --help are reserved for the built-in help"
  (spec-error (lambda () (flag "--help" "--helper" "H"))))

(check "a name that merely starts with help is fine" #f
  (spec-error (lambda () (flag "-H" "--helper" "Helper"))))

(check "reserved name inside a command spec is rejected too"
  "flag: -h and --help are reserved for the built-in help"
  (spec-error (lambda () (command "x" "X" (flag "-h" "--hard" "Hard")))))

;; --- Spec validation ---
(display "=== Spec validation ===") (newline)

;; the issue's table: each used to crash later or corrupt keys
(check "empty long name"
  "flag: long name must be \"--\" followed by a name without \"=\""
  (spec-error (lambda () (flag "-x" "" "X"))))

(check "long name without --"
  "option: long name must be \"--\" followed by a name without \"=\""
  (spec-error (lambda () (option "-n" "count" "N" 10))))

(check "long name with only --"
  "flag: long name must be \"--\" followed by a name without \"=\""
  (spec-error (lambda () (flag "-x" "--" "X"))))

(check "long name containing ="
  "option: long name must be \"--\" followed by a name without \"=\""
  (spec-error (lambda () (option "-n" "--count=5" "N"))))

(check "short name without -"
  "flag: short name must be \"-\" followed by one character"
  (spec-error (lambda () (flag "v" "--verbose" "V"))))

(check "short name too long"
  "flag: short name must be \"-\" followed by one character"
  (spec-error (lambda () (flag "-vv" "--verbose" "V"))))

(check "short name that is a long name"
  "option: short name must be \"-\" followed by one character"
  (spec-error (lambda () (option "--n" "--count" "N"))))

(check "non-string short name"
  "flag: short name must be a string"
  (spec-error (lambda () (flag 'v "--verbose" "V"))))

(check "non-string description"
  "flag: description must be a string"
  (spec-error (lambda () (flag "-v" "--verbose" 'verbose))))

(check "non-string command name"
  "command: command name must be a string"
  (spec-error (lambda () (command 42 "Answer"))))

(check "empty command name"
  "command: command name must not be empty"
  (spec-error (lambda () (command "" "Empty"))))

(check "command name that looks like an option"
  "command: command name must not start with \"-\""
  (spec-error (lambda () (command "-init" "Init"))))

(check "empty argument name"
  "argument: argument name must not be empty"
  (spec-error (lambda () (argument "" "Nothing"))))

(check "non-string app name"
  "cli: app name must be a string"
  (spec-error (lambda () (cli 'myapp "App"))))

(check "duplicate long option name"
  "cli: duplicate long option name"
  (spec-error (lambda () (cli "t" "T" (option "-a" "--count" "A" 1)
                                      (option "-b" "--count" "B" 2)))))

(check "duplicate short option name"
  "cli: duplicate short option name"
  (spec-error (lambda () (cli "t" "T" (flag "-v" "--verbose" "V")
                                      (flag "-v" "--version" "V")))))

(check "duplicate argument name"
  "cli: duplicate argument name"
  (spec-error (lambda () (cli "t" "T" (argument "file" "A")
                                      (argument "file" "B")))))

(check "duplicate command name"
  "cli: duplicate command name"
  (spec-error (lambda () (cli "t" "T" (command "init" "A")
                                      (command "init" "B")))))

(check "duplicate inside a command"
  "command: duplicate long option name"
  (spec-error (lambda () (command "build" "B" (flag "-a" "--all" "A")
                                              (flag "-b" "--all" "B")))))

(check "stray non-spec in cli"
  "cli: not a spec built by flag, option, argument or command"
  (spec-error (lambda () (cli "t" "T" "oops"))))

(check "stray non-spec in command"
  "command: not a spec built by flag, option, argument or command"
  (spec-error (lambda () (command "build" "B" '(bogus)))))

;; a hand-written list is held to the builder's shape and rules
(check "tag-shaped list with missing fields"
  "cli: not a spec built by flag, option, argument or command"
  (spec-error (lambda () (cli "t" "T" '(flag "-x")))))

(check "option list missing the default slot"
  "cli: not a spec built by flag, option, argument or command"
  (spec-error (lambda () (cli "t" "T" '(option "-n" "--count" "N")))))

(check "hand-written spec with a bad name"
  "cli: long name must be \"--\" followed by a name without \"=\""
  (spec-error (lambda () (cli "t" "T" '(flag "-x" "x" "X")))))

(check "hand-written command is validated inside"
  "command: duplicate long option name"
  (spec-error (lambda () (cli "t" "T" (list 'command "b" "B"
                                         (list (flag "-a" "--all" "A")
                                               (flag "-b" "--all" "B")))))))

;; an argument named like a same-level command could never receive that
;; word, since commands are matched first
(check "argument name colliding with a command"
  "cli: argument name is also a command name"
  (spec-error (lambda () (cli "t" "T" (command "init" "I")
                                      (argument "init" "Name")))))

(check "command name colliding with an argument"
  "cli: command name is also an argument name"
  (spec-error (lambda () (cli "t" "T" (argument "init" "Name")
                                      (command "init" "I")))))

;; the reserved-name check runs before the shape checks
(check "reserved name wins over a malformed partner"
  "flag: -h and --help are reserved for the built-in help"
  (spec-error (lambda () (flag "-h" "" "X"))))

;; still allowed
(check "subcommand may reuse a top-level option name" #f
  (spec-error (lambda () (cli "t" "T" (option "-j" "--jobs" "J" 1)
                                      (command "build" "B"
                                        (option "-j" "--jobs" "J" 4))))))

(check "same argument name in two commands is fine" #f
  (spec-error (lambda () (cli "t" "T" (command "a" "A" (argument "name" "N"))
                                      (command "b" "B" (argument "name" "N"))))))

(check "hyphenated long name is fine" #f
  (spec-error (lambda () (flag "-d" "--dry-run" "Dry run"))))

(check "option default of any type is fine" #f
  (spec-error (lambda () (option "-l" "--level" "L" 'debug))))

;; --- Help for an undeclared subcommand ---
(display "=== Help for unknown command ===") (newline)

(check "generate-help with an unknown command raises"
  "generate-help: no such command"
  (guard (e ((error-object? e) (error-object-message e)))
    (capture-output (lambda () (generate-help app "nope")))
    'returned))

(check "generate-help with an unknown command prints nothing first" ""
  (capture-output
    (lambda () (guard (e (#t #f)) (generate-help app "nope")))))

(let ((out (capture-output (lambda () (generate-help app "build")))))
  (check "generate-help with a declared command still works" #t
    (string-contains? out "myapp build — Build the project")))

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
