# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Short options may be clustered and values attached: `-vv`, `-vn 3`,
  `-n3`, `-n=3`, `-vn3`. The first value-taking option in a cluster
  swallows the rest of the token. A cluster whose first letter is not an
  option is still reported as an unknown option
- `parsed-errors` returns the usage errors recorded during a parse, as a
  list of strings (`'()` when clean); subcommand errors are included
- An `(error . proc)` entry in the `run-cli` handlers alist takes over
  usage-error reporting
- `--` ends option parsing; every later token is positional data
- Top-level options are accepted after the subcommand token
  (`mytool build -n 5`); a subcommand option of the same name wins there

### Changed
- `cli`, `command`, `flag`, `option`, and `argument` validate their
  arguments and raise with a message naming the builder: names and
  descriptions must be strings, a short name is `-` plus one character,
  a long name is `--` plus a name without `=`, command and argument names
  are non-empty and do not start with `-`, option, argument, and
  command names are unique within one level, and an argument may not
  share a name with a command at the same level. A malformed spec used to
  crash at the first invocation or halfway through a help page, or store
  values under a mangled key; a duplicate long name cross-wired the two
  options
- `flag` and `option` raise an error when given the reserved name `-h`
  or `--help`. Declaring `--help` used to store the value under the
  `"help"` key that dispatch checks, so every invocation printed help
- Every help page now has an Options section with the `-h, --help` row
  and says `[options]` in its usage line, including pages for specs that
  declare no options of their own; `-h` was already accepted there
- `run-cli` exits with status 2 on a usage error, after printing each
  message and a `--help` hint to stderr. Previously every error path
  exited 0
- A declared command with no handler entry, or an app with no commands
  and no `#f` handler, now raises an error in `run-cli` instead of
  printing "Unknown command" or the help page and exiting 0
- With commands declared but no `#f` handler, invoking the app without a
  command is a "missing command" usage error rather than a silent help
  page

### Fixed
- `generate-help` with a subcommand name that is not declared raises
  `generate-help: no such command` instead of printing the app's page
  under the unknown name, as if the command existed
- Unknown options (`--bogus`, `-z`) and, in a commands-only app, unknown
  commands are reported instead of silently dropped
- Positionals beyond the declared ones are reported as unexpected
  arguments instead of silently discarded
- An option with no usable value (`-n` at the end of argv, `-n -v`) is
  reported; it still keeps its default
- Top-level options after the subcommand token were dropped, and their
  values shifted the subcommand's positionals
- `--` was silently dropped, so a dash-leading positional could never be
  passed; `-5` alone was dropped too
- A multi-character dash token whose first letter is not an option
  (`-foo`) is reported as an unknown option; it used to be accepted as
  positional data
- `--flag=value` (e.g. `--verbose=true`) no longer crashes the parser;
  the value part is ignored and the flag is set to `#t`
- Option values no longer consume option-shaped tokens: `-n -v` now sets
  the `verbose` flag instead of making `count` the string `"-v"`, and the
  same guard applies to `--help` and `--`. Negative numbers (`-5`) and a
  lone `-` are still accepted as values. A missing value at end of argv
  still keeps the option default (error reporting is tracked separately
  in #4/#5)
- Documented numeric coercion in the README: a non-numeric value for a
  numeric option keeps the raw string (`--count=abc` → `"abc"`), and
  full Scheme number syntax is accepted (`1e3`, `1/2`, `#x10`)
- The greeter example's `farewell` subcommand printed `Goodbye, #f!` when no
  name was given

## [0.1.1] - 2026-07-26

### Fixed
- `--help`/`-h` after a subcommand now prints that subcommand's help instead
  of invoking its handler with empty parsed arguments and crashing

### Added
- `run-cli` accepts an optional explicit argv list,
  e.g. `(run-cli app handlers '("build" "--help"))`

## [0.1.0] - 2026-06-23

### Added
- CLI framework with declarative argument parsing, subcommands, and help generation
- Support for flags, options, and positional arguments
- Automatic help text generation
- CI workflow for automated testing
