---
name: pr-groups
description: Group open GitHub issues into cohesive sets, each landable as a single PR, with a merge order and a parallelism verdict. Use when the user asks which issues can be fixed in one PR, how to batch a milestone into PRs, how to plan the work for a release, or how to split a set of issues across sessions. Accepts a milestone title, a label, or a comma-separated list of issue numbers.
argument-hint: "[milestone-title | label:<name> | NNN,NNN,...]"
---

# PR Groups

Arguments: `$ARGUMENTS`

Turn a set of open issues into **groups, each of which one PR can close**, plus
the order to land them in.

This is the opposite of maximizing parallelism. Two issues in the same function
belong in one PR even though that serializes them — splitting them means two
reviews of the same code and a merge conflict between your own branches.

**Repo shape to keep in mind:** the entire library is one file,
`lib/kaappi/cli.sld` (~330 lines). Nearly every bug fix touches it, so
"disjoint files" parallelism barely exists for library changes and most groups
serialize on merge. The grouping question in this repo is *which part of the
file*, not *which file*: functions, arms of one `cond`, and the `;;;` banner
sections (spec builders / parser / helpers / help generation / run-cli).

## 1. Scope the set

Interpret the argument:

| Argument shape | Query |
|---|---|
| empty | `gh issue list --state open --limit 500 --json number,title,labels,assignees` |
| a milestone title (e.g. `0.1.2`) | add `--milestone "<title>"` |
| `label:<name>` | add `--label "<name>"` (repeat per comma-separated label; they AND) |
| comma-separated numbers | fetch exactly those with `gh issue view` |

If a filter returns nothing, say so and stop. Never silently widen to the whole
tracker. If the returned count equals the limit, raise the limit and rerun.

Drop from consideration, and say which you dropped and why: epics and tracking
issues, issues already assigned, issues with an open linked PR, and anything
labelled blocked / blocked-upstream / wontfix / duplicate. (The `audit` label
marks the 2026-09 bug-review set; it is a filter, not a drop reason.)

## 2. Read the bodies

Titles almost never name files; bodies usually do, often with line numbers.
Every rule below depends on knowing which code an issue touches, so fetch
bodies:

```bash
gh issue list --state open --limit 500 --label "audit" --json number,title,labels,body
```

For a large set, write the bodies to a scratch file and read that rather than
paging them through several tool calls.

## 3. Verify each issue still reproduces

**Do this before grouping, not after.** An issue can have been fixed by a PR
that closed its siblings and never got closed itself — scheduling it wastes a
slot in the plan and, worse, makes the whole plan look untrustworthy when
someone discovers it.

Repros here run against the working copy with the Kaappi interpreter:

```bash
kaappi --lib-path lib /tmp/repro.scm        # from the repo root
```

Build the interpreter first if absent (CONTRIBUTING.md: Zig 0.16.0, clone
`kaappi/kaappi`, `zig build`). Two hazards: an `kaappi` binary already on PATH
(or `thottam`-installed) can predate the interpreter behavior an issue depends
on — build fresh when an issue hinges on interpreter semantics; and always run
from the repo root with `--lib-path lib` so `(import (kaappi cli))` resolves
to the working copy.

Nearly every issue in this tracker carries a one-liner repro via
`run-cli-parse` — cheap enough to verify the whole set. Skip anything needing a
special build or hardware unless the grouping hinges on it.

Report anything that no longer reproduces as **verify-and-close**, with the
observed output next to the issue's own "Expected" block, and leave it out of
the groups. Do not close it yourself unless the user asks.

Also check whether a merged PR already claims the area: if several sibling
issues were closed together, ask whether this one was simply missed.

## 4. Ground the file claims in the source

An issue's diagnosis is a hypothesis, and hypotheses in this tracker have been
wrong often enough to be worth a minute of checking. Before grouping on a
claim, confirm it:

```bash
grep -n 'coerce\|set-opt\|match-positional' lib/kaappi/cli.sld  # do the named sites exist?
grep -n '^    ;; ===\|^    ;; ---' lib/kaappi/cli.sld           # section map
```

What you are looking for is cheap and specific:

- Do the two issues you want to pair really sit in the same function or the
  same `cond`, or just in the same section?
- Is the "one-line fix" one line? (Line numbers in issues drift fast in a
  single small file — re-anchor them.)
- Does the fix stay inside the public behavior contract (AGENTS.md hard
  rules: coercion semantics, `--help` routing, help layout)? If not, the
  group is a breaking change and must be planned as one.

A grouping built on a stale line number falls apart on contact.

## 5. Group by cohesion

Strongest signal first — pair on the highest one that applies:

1. **Same function, or adjacent arms of one `cond`.** One diff, one review.
   The `cond` in `parse-args` is the classic case: the help branch and the
   three option branches live within ~50 lines and share the value-consumption
   logic, so their bugs fix each other.
2. **Same `;;;` section.** Parser / help generation / run-cli / spec builders.
   One reviewer context, one shared test update.
3. **Same root cause across sections.** State the shared cause in one
   sentence; if you cannot, it is not a group.
4. **Same verification harness.** Fixes proven by one `dispatch`-based
   help-output batch, or one `run-cli-parse` assertion batch, group well even
   when otherwise unrelated.
5. **Same zero-risk class.** Tests-only (`tests/test-cli.scm`),
   examples-only (`examples/`), or docs-only (README/CHANGELOG) changes batch
   broadly and are trivially splittable — say so.

**Not a signal in this repo: "same file."** Everything library-side is the
same file; treat it as the floor, not a reason to group.

Do **not** group:

- A fix needing a design decision with one that doesn't. The design discussion
  will hold the whole PR hostage. The recurring example here: how strict error
  handling should be (unknown options, missing values, exit codes) is a policy
  decision the maintainer must make; pair it with nothing.
- A library-behavior change with local fixes, for the same reason.
- Issues whose only link is a shared label or milestone.

Keep a group to what one reviewer can hold at once. Beyond roughly four issues,
split unless they are the zero-risk class — and in a 330-line file, four fixes
is already a fifth of the library, so lean toward three.

## 6. Check what the grouped edits would blow

The kaappi constraints that only bite in aggregate:

- **Merge interleaving, not file size.** Parallel groups editing
  `lib/kaappi/cli.sld` *will* conflict with each other — there is only one
  library file. Library-touching groups land in sequence (or rebase on each
  other); only groups confined to `tests/`, `examples/`, and README/CHANGELOG
  can merge in any order.
- **Docs-sync obligations (AGENTS.md).** Every group must plan its README
  example updates (they are shown verbatim), its `CHANGELOG.md`
  `## [Unreleased]` entry, and its tests. A group touching help output must
  budget for a README rewrite, not just a code diff.
- **The public behavior contract.** A group that changes option coercion,
  `--help` routing, or help layout is a breaking change: flag it, label the PR
  `breaking`, and note that `kaappi.pkg` version bumps happen only at release
  — never inside a group.

## 7. Order the groups

- **Tests come with the fix.** AGENTS.md requires a test alongside every
  behavior change, so a group is not done without one. A test-only PR that
  pins today's (buggy) behavior ahead of the fix wave is optional but makes
  each subsequent fix's diff self-evident.
- **Signal before work.** If an issue makes CI produce false reds (or the test
  suite lie), it goes first — every later PR's CI is untrustworthy otherwise,
  and someone burns time disproving a failure they did not cause.

Then: groups confined to disjoint trees (`tests/`+docs vs `examples/` vs the
library) run **in parallel**. Library groups land in sequence. Groups needing
a design decision go last, on their own.

Apply any dependency stated in a body ("depends on", "blocked by", "after #NNN
lands") as a hard edge; a satisfied edge (target already closed) is not an edge.

## 8. Name the long pole

Say explicitly which group gates the release, and whether the remaining groups
are shippable without it. If they are, say so in one sentence — it is the most
actionable thing in the whole plan, because it converts a blocked release into
a scoping decision the user can make. In this repo the usual long pole is the
error-handling design decision (strictness + exit codes), and any
breaking-change group gates the version number (semver), not just the release.

## Output format

For each group: a letter, the issue numbers, the files, and one sentence on why
they are one PR. Then the order, then the caveats.

```text
A — #2 + #7 · option value handling (adjacent arms of parse-args's cond)
    files: lib/kaappi/cli.sld:119-162, tests/test-cli.scm
    <one sentence: why one PR>

B — #9 + #15 · help generation edge cases
    files: lib/kaappi/cli.sld:230-300
```

Follow with the order as a short diagram:

```text
A  →  B  (library groups: sequential, same file)  ‖  C (examples-only: parallel)
→  D  (design-first)
```

Close with: anything that no longer reproduces (from step 3), any repo
constraint a group would blow (step 6), and the long-pole sentence (step 8).

If the user wants to launch concurrent sessions rather than review a plan, also
emit the group leaders as bare paste-able lines, one wave per line, containing
nothing else:

```text
Wave 1: NNN, NNN
Wave 2: NNN
```

Waves come from the order in step 7. Expect most waves here to be size 1 for
library groups; a wave of 2+ means a library group plus groups confined to
tests/examples/docs.

## 9. Working the PRs — one git worktree per group

The plan is the deliverable. But when the user says to *start* a wave — "start
wave 1", "launch these", "go" — each group becomes a PR, and **every PR is built
on its own git worktree**. Never work two groups in the shared checkout, and
never commit a group's fix onto `main`: a worktree gives each session an
isolated copy of the repo on its own branch, so concurrent sessions cannot
collide on files or on the working tree, and a stalled or abandoned group leaves
nothing to clean up in the others.

Every branch is cut from a **freshly-fetched `origin/main`**, not from whatever
the local checkout happens to sit at — the checkout you are running in can be
behind (a session branched from a stale local `main` builds on old code and
rebases painfully later, or conflicts on a file the tip already changed). So the
first act of any session is `git fetch origin`, and the branch is `origin/main`.

Launch one session per group in the wave, each in a worktree:

- **Preferred: the `Agent` tool with `isolation: "worktree"`**, one call per
  group, all groups of a wave in a single message so they run concurrently. The
  worktree is created at the parent checkout's current commit, which may be
  stale — so the brief must tell the session to `git fetch origin` and reset its
  branch onto `origin/main` before it starts (`git checkout -b <branch>
  origin/main`, or `git reset --hard origin/main` on the worktree branch). The
  agent starts fresh, so the prompt must also be self-contained — name the issue
  numbers, tell it to `gh issue view` each body in full (the plan's file/line
  claims are stale often enough to re-check), and state the deliverable below.
- **Or, driving it yourself:** `git fetch origin` then
  `git worktree add ../wt-<group> -b <branch> origin/main`, do the work there,
  and `git worktree remove` when the PR is up.

Give every session the same wrap-up contract, and hold it to finishing — a
session that stops with the fix uncommitted has produced nothing:

- Branch from the freshly-fetched `origin/main` (above); implement the fix **and
  its regression test** (AGENTS.md requires tests alongside every behavior
  change), plus the `CHANGELOG.md` entry and any README example updates.
- Commit with a DCO sign-off — `git commit -s`; do not hand-write the
  `Signed-off-by` trailer (the repo enforces DCO via the DCO2 app). Subjects:
  short, imperative (`Fix crash on subcommand --help`).
- Push the branch and open the PR with `gh pr create`. The body repeats the
  closing keyword **per issue** (`Closes #NNN` on its own line for each —
  "Closes #A, #B" closes only #A).

Two operational gotchas, both of which cost a session in practice:

- **Run the test suite in the foreground**, as one blocking call from the
  worktree root — `kaappi --lib-path lib tests/test-cli.scm`, exit 0 required —
  never backgrounded waiting on a completion notification the session will not
  receive. A session that backgrounds its tests and stops "to wait" stalls
  indefinitely.
- **Run tests from *inside* the worktree** so `--lib-path lib` resolves to that
  worktree's `lib/` — an absolute path into another checkout silently tests the
  wrong code. The interpreter itself is built once and shared (typically
  `/tmp/kaappi`, per CONTRIBUTING.md); do not rebuild it mid-wave — concurrent
  `zig build` runs serialize on the shared Zig cache and look hung for minutes.

After a wave lands, verify the merge base rather than trusting each session's
"tests pass": a green run inside one worktree does not prove `main` is green, and
a *pre-existing* red (a flaky or already-broken test on `main`) will be reported
by every session as if it were theirs — confirm it against a clean checkout
before treating it as a wave regression. A real pre-existing red is itself a
signal-before-work item (step 7) for the next wave.
