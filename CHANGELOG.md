# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Fixed
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
