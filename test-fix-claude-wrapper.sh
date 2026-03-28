#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TARGET_SCRIPT="$SCRIPT_DIR/fix-claude-wrapper.sh"

say() {
  printf '%s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

run_step() {
  label="$1"
  shift
  say ""
  say "==> $label"
  "$@"
}

assert_exists() {
  path="$1"
  [ -e "$path" ] || [ -L "$path" ] || die "Expected path missing: $path"
  say "exists: $path"
}

assert_runs() {
  path="$1"
  "$path" --version >/dev/null 2>&1 || die "Expected command to run: $path --version"
  say "runs: $path -> $($path --version)"
}

main() {
  [ -x "$TARGET_SCRIPT" ] || die "Target script is not executable: $TARGET_SCRIPT"

  run_step "Help output" "$TARGET_SCRIPT" help
  run_step "Dry preflight" "$TARGET_SCRIPT" dry-test
  run_step "Doctor before install" "$TARGET_SCRIPT" doctor
  run_step "Install managed wrapper" "$TARGET_SCRIPT" install
  run_step "Post-install validation" "$TARGET_SCRIPT" post-test
  run_step "Matrix validation" "$TARGET_SCRIPT" matrix-test
  run_step "Doctor after install" "$TARGET_SCRIPT" doctor
  run_step "Help output after install" "$TARGET_SCRIPT" --help

  say ""
  say "==> Verifying expected compatibility paths"
  assert_exists "$HOME/.local/bin/claude"
  assert_exists "$HOME/.claude/bin/claude"
  assert_exists "$HOME/.claude/local/claude"
  assert_exists "$HOME/.npm-global/bin/claude"

  say ""
  say "==> Verifying compatibility paths execute"
  assert_runs "$HOME/.local/bin/claude"
  assert_runs "$HOME/.claude/bin/claude"
  assert_runs "$HOME/.claude/local/claude"
  assert_runs "$HOME/.npm-global/bin/claude"

  say ""
  say "All wrapper tests passed."
}

main "$@"
