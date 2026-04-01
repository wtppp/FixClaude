# FixClaude

A small compatibility toolkit that makes a Claude Code CLI discoverable from user-level locations expected by desktop wrappers, GUI apps, and similar launch environments.

It is intentionally broader than npm-only repair. The toolkit supports pnpm/npm-style installs, regenerates a managed runtime wrapper, maintains compatibility links, and includes validation flows aimed at GUI-like execution environments.

## What it manages

Primary managed wrapper:

- `~/.local/bin/claude`

Compatibility links:

- `~/.claude/bin/claude`
- `~/.claude/local/claude`
- `~/.npm-global/bin/claude`

Optional compatibility link:

- `~/.bun/bin/claude` when `ENABLE_BUN_COMPAT=1`

Managed files are marked with:

- `# managed-by: fix-claude-wrapper`

## Files in this repo

- `fix-claude-wrapper.sh` — main install / repair / validation toolkit
- `test-fix-claude-wrapper.sh` — end-to-end regression runner
- `CLAUDE.md` — project notes and maintenance guidance for this repo

## Requirements

- macOS or a Unix-like environment with POSIX shell utilities
- A working Claude Code installation available somewhere on the machine
- `python3` is optional but preferred for better path discovery and path resolution

Without Python, the script still works with a narrower shell fallback strategy.

## Quick start

Run a non-invasive preflight first:

```sh
./fix-claude-wrapper.sh dry-test
```

Install or refresh the managed wrapper set:

```sh
./fix-claude-wrapper.sh install
```

If wrapper discovery, links, cached state, or GUI execution seem broken, rebuild the managed wrapper set:

```sh
./fix-claude-wrapper.sh repair
```

Validate the generated wrapper and compatibility links:

```sh
./fix-claude-wrapper.sh post-test
./fix-claude-wrapper.sh matrix-test
```

Run the full regression script:

```sh
./test-fix-claude-wrapper.sh
```

## Command summary

```sh
./fix-claude-wrapper.sh help
./fix-claude-wrapper.sh doctor
./fix-claude-wrapper.sh dry-test
./fix-claude-wrapper.sh install
./fix-claude-wrapper.sh repair
./fix-claude-wrapper.sh post-test
./fix-claude-wrapper.sh matrix-test
./fix-claude-wrapper.sh uninstall
```

## Command intent

- `install` — install the managed Claude wrapper set, or refresh it if already present
- `repair` — rebuild the managed wrapper set when detection or execution is broken
- `doctor` — print current diagnosis and detected resources
- `dry-test` — run preflight checks without modifying files
- `post-test` — validate managed wrapper and compatibility links, including GUI-like execution
- `matrix-test` — run the broadest built-in validation matrix across paths, targets, state, and GUI-like execution
- `uninstall` — remove only files managed by this toolkit

## Design notes

### Python is optional

When available, Python 3 is used for:

- richer filesystem discovery
- better candidate ranking for `cli.js`
- more complete realpath resolution

When Python is unavailable, the script falls back to shell-based discovery for core operations.

### Shell fallback limitations

The shell fallback is intentionally narrower than the Python-assisted path scan. Known limitations include:

- no deep recursive search quality comparable to Python globbing
- weaker scoring and ranking across multiple `cli.js` candidates
- more reliance on common install locations and nearby inferred paths
- less complete path resolution behavior

## Safety model

- Do not overwrite unrelated working Claude binaries casually
- Only remove files marked as managed by this toolkit
- Prefer backup plus atomic replacement when updating managed files

## Validated compatibility targets

Compatibility investigation was specifically done against:

- CodePilot (`op7418/CodePilot`)
- ClaudePrism (`delibae/claude-prism`)

Important ClaudePrism-specific note:

- it checks `~/.claude/local/claude`, so that path remains part of the managed compatibility set

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

No license file is included yet. Add one before distributing under a specific open source license.
