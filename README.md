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

Every builder validates its arguments when the spec is built and raises
an error naming the builder and the offending value: a short name must be
`-` plus one character, a long name `--` plus a name without `=`, a
command or argument name is non-empty and does not start with `-`, and
names and descriptions must be strings. `cli` and `command` accept only
specs made by these builders, and reject a duplicate option, argument, or
command name within their own level, as well as an argument named like a
command at the same level. A subcommand may reuse a top-level option
name; see [Option Placement](#option-placement).

### Parsing

```scheme
(run-cli app handlers)         ; parse command-line, dispatch to handler
(run-cli app handlers argv)    ; same, but parse an explicit argv list
(run-cli-parse app argv)       ; parse explicit argv list (for testing)
```

`handlers` is an alist: one `("name" . proc)` entry per subcommand, a
`(#f . proc)` entry for invocations without a subcommand, and an optional
`(error . proc)` entry for usage errors (see [Usage Errors](#usage-errors)).
Command keys are strings; the error key is the symbol `error`, not the
string `"error"`. Each `proc` receives the parsed result.

### Result Access

```scheme
(parsed-ref result "name")     ; get option value by long name (without --)
(parsed-flag? result "verbose") ; check if flag is set
(parsed-args result)           ; positional args as alist
(parsed-command result)        ; subcommand name or #f
(parsed-sub result)            ; parsed result for subcommand
(parsed-errors result)         ; usage errors as a list of strings, '() if none
```

### Help

```scheme
(generate-help app)            ; print help for main app
(generate-help app "build")    ; print help for subcommand
```

`generate-help` raises an error when the subcommand name is not declared
in `app`, rather than printing a page for a command that does not exist.

`--help` and `-h` are handled automatically, at the top level and after a
subcommand: `mytool --help` prints the app help, `mytool build --help`
prints help for the `build` subcommand. Every help page lists the
`-h, --help` row, including pages for specs that declare no options of
their own.

Because of that, `-h` and `--help` are reserved: `flag` and `option`
raise an error when given either name, so the collision is caught when
the spec is built rather than at the first invocation.

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

Each subcommand gets its own help page:

```
$ kaappi mytool.scm build --help
mytool build — Build

Usage: mytool build [options]

Options:
  -j, --jobs <value>        Parallel jobs (default: 4)
  -h, --help                Show this help
```

## Option Placement

Top-level options may come before or after the subcommand token: with a
top-level `--verbose` flag, `mytool -v build` and `mytool build -v` are
equivalent. When a subcommand declares an option with the same name, the
subcommand's wins after its token; put the top-level one before it.

Short options may be clustered, and a value may be attached to its option:
`-vv`, `-vn 3`, `-n3`, `-n=3` and `-vn3` all work as in getopt. The first
option in a cluster that takes a value swallows the rest of the token, so
`-nv` is `count` = `"v"`, not `-n` plus `-v`.

`--` ends option parsing. Every later token is positional data, so
`mytool -- -x` passes `-x` as the argument. A dash-leading token that reads
as a real number (`-5`, `-1.5e2`) is always taken as data, and the lone `-`
is an ordinary value.

## Usage Errors

The parser reports input it cannot use instead of ignoring it:

- an option that is not declared: `--bogus`, `-z`
- an option without a value: `-n` at the end of argv, or `-n -v`
- a bare word that is not a declared command, when the app has commands
  but no positional arguments; later bare words are taken as that
  command's arguments and not reported, later options still are
- a dash-leading token whose first letter is not an option (`-foo`)
- more positionals than declared
- no command given, when the app has commands but no `#f` handler

`run-cli` prints each message to stderr prefixed with the app name, adds a
`--help` hint, and exits with status 2. Parsing continues past an error so
every problem in the invocation is reported at once.

```
$ kaappi mytool.scm bulid
mytool: unknown command 'bulid'
Try 'mytool --help' for more information.
$ echo $?
2
```

`--help` anywhere in argv still prints help and exits 0, even when the
rest of the invocation has errors.

To report errors yourself, add an entry keyed by the symbol `error` to the
handlers alist. It receives the parsed result, `(parsed-errors result)` lists the messages,
and `run-cli` returns after calling it instead of exiting:

```scheme
(run-cli app
  `((#f . ,main)
    (error . ,(lambda (r)
                (for-each (lambda (m) (display m) (newline)) (parsed-errors r))
                (exit 64)))))
```

`run-cli-parse` never exits: it returns the result with the errors recorded,
which is what tests should use. Errors from a subcommand parse appear in the
top-level list and in the subcommand result's own list.

Two situations are bugs in the program rather than in the invocation, so
`run-cli` raises an error instead: a declared command with no entry in
`handlers`, and an app with no commands and no `#f` handler.

## Type Coercion

Option types are inferred from the default value:
- Number default (`10`) → value parsed as a number with `string->number`
- String default (`"out.txt"`) → value kept as string
- No default → string

If the value does not parse as a number, the raw string is kept as-is
rather than raising an error: `--count=abc` → `"abc"`. Downstream code
that expects a number should check the parsed value first.

A flag ignores any `=value` suffix: `--verbose=false` sets the flag to
`#t` exactly like `--verbose` — the value part is not interpreted.

`string->number` accepts the full Scheme number syntax, so the parsed
value can differ from the default's type: `--count=1e3` → `1000.0`
(inexact), `--count=1/2` → the rational `1/2`, `--count=#x10` → `16`.

## License

MIT
