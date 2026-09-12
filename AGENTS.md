# AGENTS.md

Guidance for AI coding agents working in this repository. The full contributor
guide is [CONTRIBUTING.md](CONTRIBUTING.md); this file is the operational
subset.

## What this is

kaappi-cli is a CLI framework for [Kaappi Scheme](https://github.com/kaappi/kaappi)
(declarative argument parsing, subcommands, help generation). Pure Scheme,
no build step. The entire library is one file: `lib/kaappi/cli.sld`.

## Commands

Build the Kaappi interpreter once (needed to run anything; requires Zig 0.16.0 —
same steps as CI):

```bash
git clone --depth 1 https://github.com/kaappi/kaappi.git /tmp/kaappi
cd /tmp/kaappi && zig build
```

Run the test suite — always run before finishing any change; it must exit 0:

```bash
/tmp/kaappi/zig-out/bin/kaappi --lib-path lib tests/test-cli.scm
```

If a `kaappi` binary is already on PATH, use it instead, but keep the
`--lib-path lib` flag: it is what makes `(import (kaappi cli))` resolve to
this repo's `lib/` rather than an installed package.

Kaappi resolves bindings from libraries a file did not import, so it cannot
tell you about a missing import. CI also runs the suite under Chibi Scheme,
which enforces R7RS import partitioning; to check locally:

```bash
chibi-scheme -I lib tests/test-cli.scm
```

Coverage (CI also uploads this) and the example:

```bash
/tmp/kaappi/zig-out/bin/kaappi --coverage-xml coverage.xml --lib-path lib tests/test-cli.scm
/tmp/kaappi/zig-out/bin/kaappi --lib-path lib examples/greeter.scm Alice
```

## Hard rules

- **All library code goes in `lib/kaappi/cli.sld`.** New public API must be
  added to the `(export ...)` list of the `define-library`.
- **R7RS-small only.** Imports are limited to `(scheme base)`, `(scheme write)`,
  `(scheme char)`, `(scheme process-context)`, `(scheme cxr)`. No SRFIs, no
  host extensions — hand-roll helpers instead (see `filter`, `list-ref` in the
  library).
- **Don't break the public behavior contract:** option values coerce by
  inferred type (number default → number result), `--help`/`-h` works at the
  top level and after a subcommand, and help pages keep their layout
  (title, Usage, Options, Arguments, Commands). Changes here are breaking
  changes; say so in the changelog.
- **Every commit needs a DCO sign-off** (`git commit -s`). The repo enforces
  it.
- **Commit subjects:** short, imperative, matching existing history
  (`Fix crash on subcommand --help`).

## Code style

- 4-space indentation.
- `;;;` banner comments separate sections (spec builders / parser / helpers /
  help generation / run-cli) — place new code in the right section.
- `;;` comments on spec builders show an example invocation; keep that
  pattern for new builders.

## Tests

`tests/test-cli.scm` is a self-contained script, not a framework. Use the
existing helpers:

- `(check "name" expected actual)` for assertions.
- `(run-cli-parse app '(...))` for parsing behavior.
- The `dispatch` helper (captures output, resets `last-call`) for asserting
  both printed help text (`string-contains?`) and whether handlers ran.

Add tests alongside every behavior change. Do not introduce a test framework
or SRFI test library.

## Docs that must stay in sync

- `README.md` — its examples are shown verbatim; update when adding or
  changing public API or help output.
- `CHANGELOG.md` — every user-visible change gets an entry under
  `## [Unreleased]` (Keep a Changelog headings: Added / Changed / Fixed).
- `kaappi.pkg` — version bumps happen only as part of a release
  (`Release vX.Y.Z` commit + `vX.Y.Z` tag), not per-change.
