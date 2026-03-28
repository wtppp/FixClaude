# CLAUDE.md

## Project purpose

This directory contains a local compatibility toolkit for making a pnpm/npm-installed Claude Code CLI discoverable by desktop wrappers and GUI apps that expect Claude to exist in user-level well-known locations.

Primary artifacts:
- `fix-claude-wrapper.sh` — main installer / repair / validation toolkit
- `test-fix-claude-wrapper.sh` — end-to-end regression runner for the main script

## Supported compatibility paths

The managed primary wrapper is installed at:
- `~/.local/bin/claude`

The script also maintains compatibility links at:
- `~/.claude/bin/claude`
- `~/.claude/local/claude`
- `~/.npm-global/bin/claude`

Optional compatibility link:
- `~/.bun/bin/claude` when `ENABLE_BUN_COMPAT=1`

## Main workflow

### Preflight
Run a non-invasive preflight first:

```sh
./fix-claude-wrapper.sh dry-test
```

### Install or repair

```sh
./fix-claude-wrapper.sh install
# or
./fix-claude-wrapper.sh repair
```

### Post-install validation

```sh
./fix-claude-wrapper.sh post-test
./fix-claude-wrapper.sh matrix-test
```

### Full regression script

```sh
./test-fix-claude-wrapper.sh
```

## Command summary

Useful commands:

```sh
./fix-claude-wrapper.sh help
./fix-claude-wrapper.sh doctor
./fix-claude-wrapper.sh dry-test
./fix-claude-wrapper.sh install
./fix-claude-wrapper.sh post-test
./fix-claude-wrapper.sh matrix-test
./fix-claude-wrapper.sh uninstall
```

## Design notes

### Python is optional
The toolkit prefers Python 3 for richer filesystem discovery and path scoring, but it must keep working without Python when possible.

Current policy:
- Use Python when available for deeper discovery and better candidate ranking.
- Provide shell fallbacks for core operations where feasible.
- Runtime wrappers should not depend exclusively on Python to launch Claude.

### Fallback limitations
Shell fallback is intentionally narrower than Python-assisted discovery.

Known limitations without Python:
- no deep recursive search quality comparable to Python globbing
- weaker scoring/ranking of multiple candidate `cli.js` paths
- more reliance on common install locations and nearby inferred paths
- realpath behavior is less complete than Python-backed resolution

These limits are intentional and should remain documented in the main script help output.

## Validation philosophy

The toolkit should support three layers of confidence:

1. `dry-test` — non-invasive preflight
2. `post-test` — generated wrapper/link validation
3. `matrix-test` — broadest built-in validation across paths, target resolution, state, and GUI-like execution

The dedicated regression script should continue to exercise all major commands in sequence.

## Safety / ownership rules

- Do not overwrite unrelated working Claude binaries casually.
- Managed wrappers are identified by the marker:
  - `# managed-by: fix-claude-wrapper`
- `uninstall` should only remove files managed by this toolkit.
- Prefer backup + atomic replacement when updating managed files.

## Known validated target projects

Compatibility investigation was specifically done against:
- CodePilot (`op7418/CodePilot`)
- ClaudePrism (`delibae/claude-prism`)

Important ClaudePrism-specific note:
- it checks `~/.claude/local/claude`, so that path must remain part of the managed compatibility set.

## If you modify this toolkit later

When making changes:
1. update `fix-claude-wrapper.sh`
2. update `test-fix-claude-wrapper.sh` if command surfaces or expected behavior changed
3. re-run:

```sh
./test-fix-claude-wrapper.sh
```

4. keep help text aligned with real fallback behavior and limitations
