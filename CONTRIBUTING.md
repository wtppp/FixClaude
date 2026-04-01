# Contributing

Thanks for contributing to FixClaude.

## Scope

This repository maintains a local compatibility toolkit for making Claude Code discoverable from user-level locations expected by desktop wrappers, GUI apps, and similar launch environments.

Keep changes aligned with that goal. Avoid narrowing the project into an npm-only repair script unless the repository direction explicitly changes.

## Before you change code

Read these files first:

- `README.md`
- `CLAUDE.md`
- `fix-claude-wrapper.sh`
- `test-fix-claude-wrapper.sh`

## Core maintenance rules

- Keep the project package-manager-agnostic where practical
- Preserve the managed compatibility set unless there is a deliberate compatibility decision to change it
- Keep help text aligned with actual behavior
- Keep Python optional; do not make runtime wrapper launch depend exclusively on Python
- Do not casually overwrite unrelated Claude binaries
- `uninstall` must only remove files managed by this toolkit
- Prefer backup plus atomic replacement when updating managed files

Managed files are identified by:

- `# managed-by: fix-claude-wrapper`

## Expected workflow

1. Make the minimal change needed
2. Update `fix-claude-wrapper.sh`
3. Update `test-fix-claude-wrapper.sh` if command surface or behavior changes
4. Update `README.md` and `CLAUDE.md` if user-facing behavior or project positioning changed
5. Re-run the regression flow

## Validation

Recommended validation sequence:

```sh
./fix-claude-wrapper.sh dry-test
./fix-claude-wrapper.sh repair
./fix-claude-wrapper.sh post-test
./fix-claude-wrapper.sh matrix-test
./test-fix-claude-wrapper.sh
```

At minimum, changes should leave the built-in validation commands and the regression runner passing.

## Commit guidance

Prefer small, focused commits with messages that explain the purpose of the change.

Examples:

- `Clarify wrapper command semantics.`
- `Improve wrapper discovery fallback.`
- `Add compatibility validation coverage.`

## Pull requests

A good pull request should include:

- a short summary of the change
- why the change is needed
- what commands you ran to validate it
- any compatibility impact on managed wrapper/link paths

## Documentation expectations

If you change command behavior, discovery rules, fallback behavior, or managed paths, update the docs in the same change.

In particular, keep these aligned:

- `fix-claude-wrapper.sh help` output
- `README.md`
- `CLAUDE.md`
- tests that assert behavior
