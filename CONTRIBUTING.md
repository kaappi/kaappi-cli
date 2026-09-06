# Contributing to kaappi-cli

Thanks for your interest in contributing! kaappi-cli is a small, pure-Scheme
CLI framework for [Kaappi Scheme](https://github.com/kaappi/kaappi): one
library file, one test file, no build step for the library itself. This guide
covers what you need to hack on it.

## Project layout

```
lib/kaappi/cli.sld    The entire library — spec builders, parser, help generation
tests/test-cli.scm    Test suite (plain Scheme, no test framework)
examples/greeter.scm  Example CLI app with flags, options, and a subcommand
kaappi.pkg            Package manifest (name, version, kaappi-version)
.github/workflows/ci.yml  CI: builds Kaappi, runs tests with coverage
CHANGELOG.md          Keep a Changelog format
```

## Prerequisites

The library itself is pure Scheme, but running the tests requires the
[Kaappi](https://github.com/kaappi/kaappi) interpreter, which is written in
Zig:

- [Zig](https://ziglang.org/) 0.16.0 (the version CI pins)
- git

## Getting set up

Build the interpreter once and point the tests at it:

```bash
# Build Kaappi from source (CI does exactly this)
git clone --depth 1 https://github.com/kaappi/kaappi.git /tmp/kaappi
cd /tmp/kaappi && zig build
# Produces the interpreter at /tmp/kaappi/zig-out/bin/kaappi
```

Then, from your kaappi-cli checkout, run the test suite:

```bash
/tmp/kaappi/zig-out/bin/kaappi --lib-path lib tests/test-cli.scm
```

`--lib-path lib` is what makes `(import (kaappi cli))` resolve to this repo's
`lib/` directory rather than an installed package — use it whenever you run
anything against your working copy.

To verify a code path's statement coverage locally, mirror what CI does:

```bash
/tmp/kaappi/zig-out/bin/kaappi --coverage-xml coverage.xml --lib-path lib tests/test-cli.scm
```

To try the example interactively:

```bash
/tmp/kaappi/zig-out/bin/kaappi --lib-path lib examples/greeter.scm Alice
/tmp/kaappi/zig-out/bin/kaappi --lib-path lib examples/greeter.scm farewell Bob
```

The test script prints a `PASS:`/`FAIL:` line per assertion and a final
summary; it exits non-zero if anything failed.

## Writing tests

There is no test framework — `tests/test-cli.scm` is a self-contained script
built on a `check` helper:

```scheme
(check "count=value" 99 (parsed-ref r "count"))
;;            ^ name  ^ expected   ^ actual
```

Useful patterns already in the file:

- **Parse tests** — call `run-cli-parse` with an explicit argv list and assert
  on the result: `(run-cli-parse app '("-n" "42"))`.
- **Dispatch tests** — use the file's `dispatch` helper, which captures
  `run-cli` output into a string and resets the `last-call` record, so you can
  assert both on printed help text (`string-contains?`) and on whether a
  handler ran.
- **Output checks** — `capture-output` plus `string-contains?` rather than
  exact string equality, so help-format tweaks don't require rewriting every
  assertion.

When you add or change behavior, add tests alongside it. If you touch help
output, also update the examples in `README.md` — they're shown verbatim.

## Code guidelines

- **Stay in `lib/kaappi/cli.sld`.** The whole library lives in one R7RS
  `define-library` with an explicit export list; new public API must be added
  to `(export ...)`.
- **Stick to the R7RS-small standard libraries.** The file imports only
  `(scheme base)`, `(scheme write)`, `(scheme char)`,
  `(scheme process-context)`, and `(scheme cxr)`. Avoid SRFIs and
  host-specific extensions — Kaappi's library surface is intentionally small,
  which is why the code hand-rolls things like `filter` and `list-ref`.
- **Match the existing style:** 4-space indentation, `;;;` section-banner
  comments to group related code, and short `;;` comments on spec builders
  showing an example invocation.
- **Keep the user-visible surface consistent:** option values coerce by
  inferred type (number default → number), `--help`/`-h` work at the top
  level and after a subcommand, and help pages follow the current layout
  (usage line, Options, Arguments, Commands). Deviations here are the kind of
  thing reviewers will flag.
- **No build step, no generated code.** Changes should be readable in place.

## Commits, DCO, and pull requests

### Sign off your commits (required)

This repo enforces the [Developer Certificate of
Origin](https://developercertificate.org/) via a DCO check. Every commit must
carry a sign-off line:

```bash
git commit -s -m "Add repeat option to greeter example"
```

which appends:

```
Signed-off-by: Your Name <your.email@example.com>
```

The sign-off asserts you wrote the change or have the right to submit it. If
you forget, the repo's DCO2 app allows retroactively signing off failed
commits without rewriting history — or just amend and force-push your own
unmerged branch.

### Commit messages

Keep them short and imperative, matching the existing history: `Fix crash on
subcommand --help`, `Add coverage upload to CI`. The subject line should
stand alone; put detail in the body if needed.

### Pull requests

1. Fork (or branch off) `main` and keep the change focused.
2. Run the test suite locally and make sure it passes.
3. Add a `CHANGELOG.md` entry under `## [Unreleased]` (use the existing
   `Added` / `Changed` / `Fixed` headings).
4. Open the PR against `main`. CI builds Kaappi and runs the tests with
   coverage on every PR, so failures there will show up in the check run.
5. Update `README.md` if your change adds or alters public API or help
   output.

## Releases (maintainers)

Releases follow the pattern already in the history (see `Release v0.1.1`):

1. Finalize the `## [Unreleased]` section in `CHANGELOG.md` as a new version
   with the release date.
2. Bump `version:` in `kaappi.pkg` (the `kaappi-version:` constraint tracks
   the minimum supported interpreter).
3. Commit as `Release vX.Y.Z`, tag `vX.Y.Z`, and push with tags.

Versioning follows [semantic versioning](https://semver.org/); since the
parser's result structures and help output are public API, treat breaking
changes to those as major.

## Reporting issues

Open a GitHub issue on [kaappi/kaappi-cli](https://github.com/kaappi/kaappi-cli)
with the Kaappi version (or the commit you built), your OS, and — for parsing
bugs — the argv list and spec that reproduce it. A failing snippet runnable
via `run-cli-parse` is the fastest way to get a fix.

## License

By contributing, you agree your contributions are licensed under the MIT
license that covers this project.
