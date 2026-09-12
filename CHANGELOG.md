# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Fixed
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
