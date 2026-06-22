---
description: Cut a GitHub release for kaappi-cli — updates CHANGELOG.md, bumps version in kaappi.pkg, commits, tags, pushes, and creates a GitHub release. Use when the user asks to make a release, cut a release, publish a version, tag a release, ship a version, or prepare a release.
---

# GitHub Release

Full kaappi-cli release process: changelog update, version bump, commit, tag, push, and GitHub release creation.

## Prerequisites

Check all three before proceeding:

```bash
git status          # must be clean
git branch --show-current  # must be main
gh auth status      # must be authenticated
```

If dirty, ask the user to commit or stash. If not on `main`, ask to switch.

## Step 1: Determine version

```bash
git tag -l 'v*' --sort=-v:refname | head -1
```

If no tags exist, the current version is `0.0.0`.

Show the current version and ask what the new version should be:

- **patch** (0.1.0 -> 0.1.1): bug fixes only
- **minor** (0.1.0 -> 0.2.0): new features, no breaking changes
- **major** (0.1.0 -> 1.0.0): breaking changes

Wait for confirmation before continuing.

## Step 2: Generate release notes

```bash
git log $(git tag -l 'v*' --sort=-v:refname | head -1)..HEAD --oneline --no-merges
```

If no tags exist yet, use `git log --oneline --no-merges`.

Combine the `[Unreleased]` section from `CHANGELOG.md` (primary source) with any commits not already reflected. Present draft notes to the user for review. Wait for confirmation.

## Step 3: Update CHANGELOG.md

The file uses Keep a Changelog format. After editing, it should look like:

```markdown
## [Unreleased]

## [X.Y.Z] - YYYY-MM-DD

### Added
- ...

### Fixed
- ...

## [previous version] - previous date
...
```

- Clear the `[Unreleased]` section content (keep the heading)
- Insert new `## [X.Y.Z] - YYYY-MM-DD` section with the confirmed release notes
- Use today's date in YYYY-MM-DD format
- Preserve all existing versioned sections below

## Step 4: Update version in kaappi.pkg

Add or update the `version:` field (no `v` prefix):

```
version: X.Y.Z
```

## Step 5: Test verification

```bash
kaappi --lib-path lib tests/test-cli.scm
```

If `kaappi` is not on PATH, try `/tmp/kaappi/zig-out/bin/kaappi --lib-path lib tests/test-cli.scm`.

Fix any failures before proceeding.

## Step 6: Commit and tag

```bash
git add CHANGELOG.md kaappi.pkg
git commit -m "Release vX.Y.Z"
git tag -a vX.Y.Z -m "Release vX.Y.Z"
```

## Step 7: Push (requires user confirmation)

**STOP.** Ask the user for explicit confirmation before pushing. Explain:

- Pushing the tag and branch is irreversible
- It will make the release publicly visible

After confirmation:

```bash
git push origin main
git push origin vX.Y.Z
```

## Step 8: Create GitHub release

```bash
gh release create vX.Y.Z --title "vX.Y.Z" --notes "RELEASE_NOTES_HERE"
```

Use the confirmed release notes from Step 2 as the `--notes` content.

## Step 9: Verify

```bash
gh release view vX.Y.Z
```

Show the release URL to the user.

## Error recovery

**Before push** (undo commit and tag):

```bash
git tag -d vX.Y.Z
git reset --soft HEAD~1
```

**After push** (if something went wrong):

```bash
git push origin --delete vX.Y.Z
gh release delete vX.Y.Z --yes
git tag -d vX.Y.Z
git reset --soft HEAD~1
# Fix the issue, then restart
```
