# kaappi-cli

CLI framework for [Kaappi Scheme](https://github.com/kaappi/kaappi) — declarative
argument parsing, subcommands, and help generation.

Pure Scheme, no build step.

```bash
thottam install kaappi-cli
```

## Quick Start

```scheme
(import (kaappi cli))

(define app
  (cli "greet" "A greeting tool"
    (flag "-l" "--loud" "Use uppercase")
    (option "-n" "--times" "Repeat N times" 1)
    (argument "name" "Name to greet")))

(run-cli app
  `((#f . ,(lambda (result)
             (let ((name (or (cdr (car (parsed-args result))) "World"))
                   (n (parsed-ref result "times")))
               (let loop ((i 0))
                 (when (< i n)
                   (display "Hello, ") (display name) (display "!") (newline)
                   (loop (+ i 1)))))))))
```

```
$ kaappi greet.scm Alice
Hello, Alice!

$ kaappi greet.scm -n 3 Bob
Hello, Bob!
Hello, Bob!
Hello, Bob!

$ kaappi greet.scm --help
greet — A greeting tool

Usage: greet [options] <name>

Options:
  -l, --loud                Use uppercase
  -n, --times <value>       Repeat N times (default: 1)
  -h, --help                Show this help

Arguments:
  <name>                    Name to greet
```

## API

### Spec Builders

```scheme
(cli name description spec ...)          ; top-level app definition

(flag short long description)            ; boolean flag (no value)
(option short long description [default]) ; option with value
(argument name description)              ; positional argument
(command name description spec ...)      ; subcommand with its own specs
```

### Parsing

```scheme
(run-cli app handlers)         ; parse command-line, dispatch to handler
(run-cli-parse app argv)       ; parse explicit argv list (for testing)
```

### Result Access

```scheme
(parsed-ref result "name")     ; get option value by long name (without --)
(parsed-flag? result "verbose") ; check if flag is set
(parsed-args result)           ; positional args as alist
(parsed-command result)        ; subcommand name or #f
(parsed-sub result)            ; parsed result for subcommand
```

### Help

```scheme
(generate-help app)            ; print help for main app
(generate-help app "build")    ; print help for subcommand
```

`--help` and `-h` are handled automatically.

## Subcommands

```scheme
(define app
  (cli "mytool" "My tool"
    (command "init" "Initialize"
      (argument "name" "Project name"))
    (command "build" "Build"
      (option "-j" "--jobs" "Parallel jobs" 4))))

(run-cli app
  `(("init" . ,(lambda (r)
                 (let ((name (cdr (car (parsed-args (parsed-sub r))))))
                   (display "Initializing ") (display name) (newline))))
    ("build" . ,(lambda (r)
                  (let ((jobs (parsed-ref (parsed-sub r) "jobs")))
                    (display "Building with ") (display jobs)
                    (display " jobs") (newline))))))
```

## Type Coercion

Option types are inferred from the default value:
- Number default (`10`) → value parsed as number
- String default (`"out.txt"`) → value kept as string
- No default → string

## License

MIT
