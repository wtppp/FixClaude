#!/bin/sh
set -eu

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

HOME_DIR="${HOME:?HOME is not set}"
LOCAL_BIN="$HOME_DIR/.local/bin"
CLAUDE_BIN_DIR="$HOME_DIR/.claude/bin"
CLAUDE_LOCAL_DIR="$HOME_DIR/.claude/local"
NPM_GLOBAL_BIN="$HOME_DIR/.npm-global/bin"
BUN_BIN_DIR="$HOME_DIR/.bun/bin"
STATE_DIR="$HOME_DIR/.cache/claude-wrapper"
STATE_FILE="$STATE_DIR/state.env"
LOCK_DIR="$STATE_DIR/lock"
BACKUP_DIR="$STATE_DIR/backups"
PRIMARY_WRAPPER="$LOCAL_BIN/claude"
CLAUDE_COMPAT_WRAPPER="$CLAUDE_BIN_DIR/claude"
CLAUDE_LOCAL_COMPAT_WRAPPER="$CLAUDE_LOCAL_DIR/claude"
NPM_COMPAT_WRAPPER="$NPM_GLOBAL_BIN/claude"
OPTIONAL_BUN_COMPAT_WRAPPER="$BUN_BIN_DIR/claude"
ENABLE_BUN_COMPAT="${ENABLE_BUN_COMPAT:-0}"
SCRIPT_MARKER="# managed-by: fix-claude-wrapper"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

has_python() {
  command_exists python3
}

resolve_path() {
  target="$1"
  if has_python; then
    python3 - "$target" <<'PY'
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
    return 0
  fi

  if command_exists readlink; then
    resolved="$(readlink "$target" 2>/dev/null || true)"
    if [ -n "$resolved" ]; then
      case "$resolved" in
        /*) printf '%s\n' "$resolved" ;;
        *) printf '%s/%s\n' "$(CDPATH= cd -- "$(dirname -- "$target")" && pwd -P)" "$resolved" ;;
      esac
      return 0
    fi
  fi

  if [ -e "$target" ] || [ -L "$target" ]; then
    printf '%s\n' "$target"
    return 0
  fi

  return 1
}

ensure_dirs() {
  mkdir -p "$LOCAL_BIN" "$CLAUDE_BIN_DIR" "$CLAUDE_LOCAL_DIR" "$NPM_GLOBAL_BIN" "$STATE_DIR" "$BACKUP_DIR"
}

acquire_lock() {
  ensure_dirs
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    trap 'release_lock' EXIT INT TERM HUP
    return 0
  fi
  die "Another claude-wrapper operation is already in progress"
}

release_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

is_ours() {
  target="$1"
  [ -f "$target" ] || return 1

  if has_python; then
    python3 - "$target" <<'PY'
import sys
path = sys.argv[1]
try:
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        data = f.read(4096)
except Exception:
    raise SystemExit(1)
raise SystemExit(0 if '# managed-by: fix-claude-wrapper' in data else 1)
PY
    return $?
  fi

  grep -q "# managed-by: fix-claude-wrapper" "$target" 2>/dev/null
}

save_state() {
  node_path="$1"
  cli_js="$2"
  ensure_dirs
  tmp="$STATE_FILE.tmp.$$"
  cat > "$tmp" <<EOF
PREFERRED_NODE='$node_path'
PREFERRED_CLI='$cli_js'
EOF
  mv "$tmp" "$STATE_FILE"
}

load_state() {
  if [ -f "$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    . "$STATE_FILE"
  fi
}

backup_file() {
  target="$1"
  [ -e "$target" ] || [ -L "$target" ] || return 0
  ts="$(date +%Y%m%d-%H%M%S)"
  cp -P "$target" "$BACKUP_DIR/$(basename "$target").$ts" 2>/dev/null || true
}

atomic_write() {
  target="$1"
  tmp="$target.tmp.$$"
  cat > "$tmp"
  chmod +x "$tmp"
  mv "$tmp" "$target"
}

find_current_claude() {
  if command_exists claude; then
    command -v claude
    return 0
  fi

  for p in \
    "$HOME/.local/bin/claude" \
    "$HOME/.claude/bin/claude" \
    "$HOME/.bun/bin/claude" \
    "/opt/homebrew/bin/claude" \
    "/usr/local/bin/claude" \
    "$HOME/.npm-global/bin/claude"
  do
    if [ -x "$p" ]; then
      printf '%s\n' "$p"
      return 0
    fi
  done

  return 1
}

find_best_node_shell() {
  for p in \
    "$(command -v node 2>/dev/null || true)" \
    "/opt/homebrew/bin/node" \
    "/usr/local/bin/node" \
    "/usr/bin/node" \
    "$HOME/.volta/bin/node" \
    "$HOME/.fnm/current/bin/node" \
    "$HOME/.nvm/current/bin/node" \
    "$HOME/.asdf/shims/node" \
    "$HOME/.local/bin/node"
  do
    if [ -n "${p:-}" ] && [ -x "$p" ]; then
      printf '%s\n' "$p"
      return 0
    fi
  done

  for p in "$HOME"/.nvm/versions/node/*/bin/node "$HOME"/.asdf/installs/nodejs/*/bin/node; do
    if [ -x "$p" ]; then
      printf '%s\n' "$p"
      return 0
    fi
  done

  return 1
}

find_best_node() {
  if has_python; then
    python3 <<'PY'
import os, subprocess

home = os.path.expanduser("~")
candidates = []
seen = set()

def add(p):
    if p and p not in seen and os.path.isfile(p) and os.access(p, os.X_OK):
        seen.add(p)
        candidates.append(p)

for shell in ["zsh", "bash"]:
    try:
        out = subprocess.check_output(
            [shell, "-ilc", "command -v node"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        if out:
            add(os.path.realpath(out))
    except Exception:
        pass

for p in [
    "/opt/homebrew/bin/node",
    "/usr/local/bin/node",
    "/usr/bin/node",
    os.path.expanduser("~/.volta/bin/node"),
    os.path.expanduser("~/.fnm/current/bin/node"),
    os.path.expanduser("~/.nvm/current/bin/node"),
    os.path.expanduser("~/.asdf/shims/node"),
    os.path.expanduser("~/.local/bin/node"),
]:
    add(p)

for base in [
    os.path.expanduser("~/.nvm/versions/node"),
    os.path.expanduser("~/.local/share/fnm"),
    os.path.expanduser("~/.asdf/installs/nodejs"),
]:
    if os.path.isdir(base):
        for root, dirs, files in os.walk(base):
            if root.count(os.sep) - base.count(os.sep) > 5:
                dirs[:] = []
                continue
            if "node" in files:
                add(os.path.join(root, "node"))

if candidates:
    print(candidates[0])
PY
    return 0
  fi

  find_best_node_shell
}

find_real_cli_js_shell() {
  current_claude="$(find_current_claude 2>/dev/null || true)"
  if [ -n "$current_claude" ]; then
    current_dir="$(dirname "$current_claude")"
    for p in \
      "$current_dir/../lib/node_modules/@anthropic-ai/claude-code/cli.js" \
      "$HOME/Library/pnpm/global/5/node_modules/@anthropic-ai/claude-code/cli.js" \
      "$HOME/.pnpm/global/5/node_modules/@anthropic-ai/claude-code/cli.js" \
      "$HOME/.local/share/pnpm/global/5/node_modules/@anthropic-ai/claude-code/cli.js" \
      "$HOME/.config/yarn/global/node_modules/@anthropic-ai/claude-code/cli.js"
    do
      if [ -f "$p" ]; then
        printf '%s\n' "$p"
        return 0
      fi
    done
  fi

  for p in \
    "$HOME"/Library/pnpm/global/*/node_modules/@anthropic-ai/claude-code/cli.js \
    "$HOME"/.pnpm/*/node_modules/@anthropic-ai/claude-code/cli.js \
    "$HOME"/.local/share/pnpm/*/node_modules/@anthropic-ai/claude-code/cli.js \
    "$HOME"/.config/yarn/global/node_modules/@anthropic-ai/claude-code/cli.js \
    "$HOME"/.bun/install/global/node_modules/@anthropic-ai/claude-code/cli.js
  do
    if [ -f "$p" ]; then
      printf '%s\n' "$p"
      return 0
    fi
  done

  return 1
}

find_real_cli_js() {
  if has_python; then
    python3 <<'PY'
import os, glob, subprocess

home = os.path.expanduser("~")
candidates = []
seen = set()

def add(path):
    if path and path not in seen and os.path.isfile(path):
        seen.add(path)
        candidates.append(path)

cmd = ""
for shell in ["zsh", "bash"]:
    try:
        cmd = subprocess.check_output(
            [shell, "-ilc", "command -v claude"],
            text=True,
            stderr=subprocess.DEVNULL
        ).strip()
        if cmd:
            break
    except Exception:
        pass

if cmd:
    real = os.path.realpath(cmd)
    add(real)
    roots = [
        os.path.dirname(real),
        os.path.dirname(os.path.dirname(real)),
        os.path.expanduser("~/Library/pnpm"),
        os.path.expanduser("~/.pnpm"),
        os.path.expanduser("~/.local/share/pnpm"),
        os.path.expanduser("~/.config/yarn"),
        os.path.expanduser("~/.bun"),
        home,
    ]

    scanned = set()
    for root in roots:
        if not root or root in scanned or not os.path.exists(root):
            continue
        scanned.add(root)
        for pattern in [
            root + "/**/@anthropic-ai/claude-code/cli.js",
            root + "/**/node_modules/@anthropic-ai/claude-code/cli.js",
        ]:
            for m in glob.glob(pattern, recursive=True):
                add(m)

if not candidates:
    for root in [
        os.path.expanduser("~/Library/pnpm"),
        os.path.expanduser("~/.pnpm"),
        os.path.expanduser("~/.local/share/pnpm"),
        os.path.expanduser("~/.config/yarn"),
        os.path.expanduser("~/.bun"),
        home,
    ]:
        if not os.path.exists(root):
            continue
        for pattern in [
            root + "/**/@anthropic-ai/claude-code/cli.js",
            root + "/**/node_modules/@anthropic-ai/claude-code/cli.js",
        ]:
            for m in glob.glob(pattern, recursive=True):
                add(m)

def score(p):
    s = 0
    if "/global/" in p:
        s += 100
    if "/node_modules/@anthropic-ai/claude-code/cli.js" in p:
        s += 50
    if "/store/" in p:
        s -= 50
    if "/projects/" in p:
        s -= 20
    return s

candidates.sort(key=lambda p: (-score(p), p))

if candidates:
    print(candidates[0])
PY
    return 0
  fi

  find_real_cli_js_shell
}

is_probably_native_binary() {
  target="$1"
  case "$target" in
    "$HOME_DIR/.local/bin/claude"|"$HOME_DIR/.claude/bin/claude")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

validate_claude() {
  target="$1"
  "$target" --version >/dev/null 2>&1
}

generate_wrapper_content() {
  node_path="$1"
  cli_js="$2"
  state_file="$STATE_FILE"
  script_path="$PRIMARY_WRAPPER"

  cat <<EOF
#!/bin/sh
set -eu
$SCRIPT_MARKER

STATE_FILE="$state_file"
SCRIPT_PATH="$script_path"
PREFERRED_NODE="$node_path"
PREFERRED_CLI="$cli_js"

load_state() {
  if [ -f "\$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    . "\$STATE_FILE"
  fi
}

rewrite_self_if_needed() {
  node_bin="\$1"
  cli_bin="\$2"
  [ -n "\${node_bin:-}" ] || return 0
  [ -n "\${cli_bin:-}" ] || return 0
  [ -w "\$SCRIPT_PATH" ] || return 0
  [ "\$node_bin" = "\$PREFERRED_NODE" ] && [ "\$cli_bin" = "\$PREFERRED_CLI" ] && return 0

  tmp="\$SCRIPT_PATH.tmp.\$\$"
  cat > "\$tmp" <<INNER
#!/bin/sh
set -eu
$SCRIPT_MARKER

STATE_FILE="$state_file"
SCRIPT_PATH="$script_path"
PREFERRED_NODE="\$node_bin"
PREFERRED_CLI="\$cli_bin"

load_state() {
  if [ -f "\\\$STATE_FILE" ]; then
    . "\\\$STATE_FILE"
  fi
}

find_node() {
  load_state
  for p in \\
    "\\\${PREFERRED_NODE:-}" \\
    "\\\${PREFERRED_NODE:-}" \\
    "\\\${PREFERRED_NODE:-}" \\
    "\\\$(command -v node 2>/dev/null || true)" \\
    "/opt/homebrew/bin/node" \\
    "/usr/local/bin/node" \\
    "/usr/bin/node" \\
    "\\\$HOME/.volta/bin/node" \\
    "\\\$HOME/.fnm/current/bin/node" \\
    "\\\$HOME/.nvm/current/bin/node" \\
    "\\\$HOME/.asdf/shims/node"
  do
    if [ -n "\\\${p:-}" ] && [ -x "\\\$p" ]; then
      printf '%s\\n' "\\\$p"
      return 0
    fi
  done
  return 1
}

find_cli() {
  load_state
  for p in "\\\${PREFERRED_CLI:-}" "\\\${PREFERRED_CLI:-}"; do
    if [ -n "\\\${p:-}" ] && [ -f "\\\$p" ]; then
      printf '%s\\n' "\\\$p"
      return 0
    fi
  done

  python3 <<'PY'
import os, glob
home = os.path.expanduser("~")
candidates = []
seen = set()
for root in [
    os.path.expanduser("~/Library/pnpm"),
    os.path.expanduser("~/.pnpm"),
    os.path.expanduser("~/.local/share/pnpm"),
    os.path.expanduser("~/.config/yarn"),
    os.path.expanduser("~/.bun"),
    home,
]:
    if not os.path.exists(root):
        continue
    for pattern in [
        root + "/**/@anthropic-ai/claude-code/cli.js",
        root + "/**/node_modules/@anthropic-ai/claude-code/cli.js",
    ]:
        for m in glob.glob(pattern, recursive=True):
            if m not in seen and os.path.isfile(m):
                seen.add(m)
                candidates.append(m)

def score(p):
    s = 0
    if "/global/" in p:
        s += 100
    if "/node_modules/@anthropic-ai/claude-code/cli.js" in p:
        s += 50
    if "/store/" in p:
        s -= 50
    if "/projects/" in p:
        s -= 20
    return s

candidates.sort(key=lambda p: (-score(p), p))
if candidates:
    print(candidates[0])
PY
}

NODE_BIN="\\\$(find_node || true)"
[ -n "\\\$NODE_BIN" ] || { echo "ERROR: node not found" >&2; exit 1; }
CLI_JS="\\\$(find_cli || true)"
[ -n "\\\$CLI_JS" ] || { echo "ERROR: Claude cli.js not found" >&2; exit 1; }
exec "\\\$NODE_BIN" "\\\$CLI_JS" "\\\$@"
INNER
  chmod +x "\$tmp"
  mv "\$tmp" "\$SCRIPT_PATH"

  mkdir -p "\$(dirname "\$STATE_FILE")"
  tmp_state="\$STATE_FILE.tmp.\$\$"
  cat > "\$tmp_state" <<STATE
PREFERRED_NODE='\$node_bin'
PREFERRED_CLI='\$cli_bin'
STATE
  mv "\$tmp_state" "\$STATE_FILE"
}

find_node() {
  load_state
  for p in \
    "\${PREFERRED_NODE:-}" \
    "\${PREFERRED_NODE:-}" \
    "\$(command -v node 2>/dev/null || true)" \
    "/opt/homebrew/bin/node" \
    "/usr/local/bin/node" \
    "/usr/bin/node" \
    "\$HOME/.volta/bin/node" \
    "\$HOME/.fnm/current/bin/node" \
    "\$HOME/.nvm/current/bin/node" \
    "\$HOME/.asdf/shims/node"
  do
    if [ -n "\${p:-}" ] && [ -x "\$p" ]; then
      printf '%s\n' "\$p"
      return 0
    fi
  done
  return 1
}

find_cli() {
  load_state
  for p in "\${PREFERRED_CLI:-}" "\${PREFERRED_CLI:-}"; do
    if [ -n "\${p:-}" ] && [ -f "\$p" ]; then
      printf '%s\n' "\$p"
      return 0
    fi
  done

  python3 <<'PY'
import os, glob
home = os.path.expanduser("~")
candidates = []
seen = set()
for root in [
    os.path.expanduser("~/Library/pnpm"),
    os.path.expanduser("~/.pnpm"),
    os.path.expanduser("~/.local/share/pnpm"),
    os.path.expanduser("~/.config/yarn"),
    os.path.expanduser("~/.bun"),
    home,
]:
    if not os.path.exists(root):
        continue
    for pattern in [
        root + "/**/@anthropic-ai/claude-code/cli.js",
        root + "/**/node_modules/@anthropic-ai/claude-code/cli.js",
    ]:
        for m in glob.glob(pattern, recursive=True):
            if m not in seen and os.path.isfile(m):
                seen.add(m)
                candidates.append(m)

def score(p):
    s = 0
    if "/global/" in p:
        s += 100
    if "/node_modules/@anthropic-ai/claude-code/cli.js" in p:
        s += 50
    if "/store/" in p:
        s -= 50
    if "/projects/" in p:
        s -= 20
    return s

candidates.sort(key=lambda p: (-score(p), p))
if candidates:
    print(candidates[0])
PY
}

NODE_BIN="\$(find_node || true)"
[ -n "\$NODE_BIN" ] || { echo "ERROR: node not found" >&2; exit 1; }
CLI_JS="\$(find_cli || true)"
[ -n "\$CLI_JS" ] || { echo "ERROR: Claude cli.js not found" >&2; exit 1; }
rewrite_self_if_needed "\$NODE_BIN" "\$CLI_JS"
exec "\$NODE_BIN" "\$CLI_JS" "\$@"
EOF
}

write_wrapper() {
  node_path="$1"
  cli_js="$2"
  backup_file "$PRIMARY_WRAPPER"
  generate_wrapper_content "$node_path" "$cli_js" | atomic_write "$PRIMARY_WRAPPER"
}

install_compat_link() {
  link_path="$1"
  mkdir -p "$(dirname "$link_path")"
  backup_file "$link_path"
  ln -sf "$PRIMARY_WRAPPER" "$link_path"
}

safe_install_links() {
  install_compat_link "$CLAUDE_COMPAT_WRAPPER"
  install_compat_link "$CLAUDE_LOCAL_COMPAT_WRAPPER"
  install_compat_link "$NPM_COMPAT_WRAPPER"
  if [ "$ENABLE_BUN_COMPAT" = "1" ]; then
    install_compat_link "$OPTIONAL_BUN_COMPAT_WRAPPER"
  fi
}

detect_resources() {
  load_state
  DETECTED_NODE="${PREFERRED_NODE:-}"
  DETECTED_CLI="${PREFERRED_CLI:-}"

  if [ -z "$DETECTED_NODE" ] || [ ! -x "$DETECTED_NODE" ]; then
    DETECTED_NODE="$(find_best_node || true)"
  fi
  if [ -z "$DETECTED_CLI" ] || [ ! -f "$DETECTED_CLI" ]; then
    DETECTED_CLI="$(find_real_cli_js || true)"
  fi
}

install_or_repair() {
  acquire_lock
  ensure_dirs

  if [ -e "$PRIMARY_WRAPPER" ] || [ -L "$PRIMARY_WRAPPER" ]; then
    existing_primary_real="$(resolve_path "$PRIMARY_WRAPPER" 2>/dev/null || true)"
    say "Existing $PRIMARY_WRAPPER -> ${existing_primary_real:-unresolved}"
    if [ ! -L "$PRIMARY_WRAPPER" ] && ! is_ours "$PRIMARY_WRAPPER" && validate_claude "$PRIMARY_WRAPPER"; then
      warn "$PRIMARY_WRAPPER already exists and works. Refusing to overwrite non-managed file."
      warn "Move it away manually if you want this script to take ownership."
      exit 2
    fi
  fi

  say "Locating usable node and Claude CLI..."
  detect_resources
  [ -n "${DETECTED_NODE:-}" ] || die "Could not locate a usable node binary"
  [ -n "${DETECTED_CLI:-}" ] || die "Could not locate @anthropic-ai/claude-code/cli.js"

  say "Found node: $DETECTED_NODE"
  "$DETECTED_NODE" --version >/dev/null 2>&1 || die "Selected node binary is not usable"

  say "Found cli.js: $DETECTED_CLI"
  [ -f "$DETECTED_CLI" ] || die "cli.js path does not exist: $DETECTED_CLI"
  "$DETECTED_NODE" "$DETECTED_CLI" --version >/dev/null 2>&1 || die "Direct node cli.js --version failed"

  save_state "$DETECTED_NODE" "$DETECTED_CLI"
  write_wrapper "$DETECTED_NODE" "$DETECTED_CLI"
  safe_install_links

  primary_version="$($PRIMARY_WRAPPER --version)"
  claude_compat_version="$($CLAUDE_COMPAT_WRAPPER --version)"
  claude_local_compat_version="$($CLAUDE_LOCAL_COMPAT_WRAPPER --version)"
  npm_compat_version="$($NPM_COMPAT_WRAPPER --version)"

  say "Done."
  say "Primary      : $PRIMARY_WRAPPER"
  say "Claude compat: $CLAUDE_COMPAT_WRAPPER -> $PRIMARY_WRAPPER"
  say "Claude local : $CLAUDE_LOCAL_COMPAT_WRAPPER -> $PRIMARY_WRAPPER"
  say "npm compat   : $NPM_COMPAT_WRAPPER -> $PRIMARY_WRAPPER"
  if [ "$ENABLE_BUN_COMPAT" = "1" ]; then
    bun_compat_version="$($OPTIONAL_BUN_COMPAT_WRAPPER --version)"
    say "bun compat   : $OPTIONAL_BUN_COMPAT_WRAPPER -> $PRIMARY_WRAPPER"
    say "bun compat V : $bun_compat_version"
  fi
  say "Node         : $DETECTED_NODE"
  say "CLI          : $DETECTED_CLI"
  say "Version      : $primary_version"
  say "Claude compatV: $claude_compat_version"
  say "Claude localV : $claude_local_compat_version"
  say "npm compat V : $npm_compat_version"
}

doctor() {
  ensure_dirs
  load_state
  say "Primary wrapper: $PRIMARY_WRAPPER"
  if [ -e "$PRIMARY_WRAPPER" ] || [ -L "$PRIMARY_WRAPPER" ]; then
    say "- exists: yes"
    if is_ours "$PRIMARY_WRAPPER"; then
      say "- managed: yes"
    else
      say "- managed: no"
    fi
  else
    say "- exists: no"
  fi

  say "Claude compat wrapper: $CLAUDE_COMPAT_WRAPPER"
  if [ -e "$CLAUDE_COMPAT_WRAPPER" ] || [ -L "$CLAUDE_COMPAT_WRAPPER" ]; then
    say "- exists: yes"
  else
    say "- exists: no"
  fi

  say "Claude local compat wrapper: $CLAUDE_LOCAL_COMPAT_WRAPPER"
  if [ -e "$CLAUDE_LOCAL_COMPAT_WRAPPER" ] || [ -L "$CLAUDE_LOCAL_COMPAT_WRAPPER" ]; then
    say "- exists: yes"
  else
    say "- exists: no"
  fi

  say "npm compat wrapper: $NPM_COMPAT_WRAPPER"
  if [ -e "$NPM_COMPAT_WRAPPER" ] || [ -L "$NPM_COMPAT_WRAPPER" ]; then
    say "- exists: yes"
  else
    say "- exists: no"
  fi

  say "bun compat wrapper: $OPTIONAL_BUN_COMPAT_WRAPPER"
  say "- enabled: $ENABLE_BUN_COMPAT"
  if [ -e "$OPTIONAL_BUN_COMPAT_WRAPPER" ] || [ -L "$OPTIONAL_BUN_COMPAT_WRAPPER" ]; then
    say "- exists: yes"
  else
    say "- exists: no"
  fi

  say "State file: $STATE_FILE"
  say "Python available: $(has_python && printf yes || printf no)"
  if [ -f "$STATE_FILE" ]; then
    say "- exists: yes"
    say "- preferred node: ${PREFERRED_NODE:-unknown}"
    say "- preferred cli : ${PREFERRED_CLI:-unknown}"
  else
    say "- exists: no"
  fi

  detect_resources
  say "Detected node: ${DETECTED_NODE:-missing}"
  say "Detected cli : ${DETECTED_CLI:-missing}"

  if [ -x "$PRIMARY_WRAPPER" ] && "$PRIMARY_WRAPPER" --version >/dev/null 2>&1; then
    say "Wrapper check: ok"
    say "Version: $($PRIMARY_WRAPPER --version)"
  else
    warn "Wrapper check failed"
  fi
}

build_test_paths() {
  TEST_PATHS=$(printf '%s\n' \
    "$PRIMARY_WRAPPER" \
    "$CLAUDE_COMPAT_WRAPPER" \
    "$CLAUDE_LOCAL_COMPAT_WRAPPER" \
    "$NPM_COMPAT_WRAPPER")
  if [ "$ENABLE_BUN_COMPAT" = "1" ]; then
    TEST_PATHS="$TEST_PATHS
$OPTIONAL_BUN_COMPAT_WRAPPER"
  fi
}

run_single_version_test() {
  path="$1"
  label="$2"
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    warn "$label missing: $path"
    return 1
  fi
  if "$path" --version >/dev/null 2>&1; then
    say "$label ok: $($path --version)"
    return 0
  fi
  warn "$label failed: $path --version"
  return 1
}

run_gui_like_test() {
  path="$1"
  label="$2"
  if env -i HOME="$HOME_DIR" PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:$HOME_DIR/.local/bin:$HOME_DIR/.bun/bin" /bin/sh -c "\"$path\" --version" >/dev/null 2>&1; then
    say "$label gui-like ok"
    return 0
  fi
  warn "$label gui-like failed"
  return 1
}

dry_test() {
  ensure_dirs
  load_state
  say "Dry test: non-invasive preflight"
  detect_resources
  say "Detected node: ${DETECTED_NODE:-missing}"
  say "Detected cli : ${DETECTED_CLI:-missing}"

  [ -n "${DETECTED_NODE:-}" ] || die "Dry test failed: no usable node detected"
  [ -n "${DETECTED_CLI:-}" ] || die "Dry test failed: no Claude cli.js detected"

  "$DETECTED_NODE" --version >/dev/null 2>&1 || die "Dry test failed: detected node is not runnable"
  "$DETECTED_NODE" "$DETECTED_CLI" --version >/dev/null 2>&1 || die "Dry test failed: detected cli.js is not runnable"

  say "Node check: $($DETECTED_NODE --version)"
  say "Claude check: $($DETECTED_NODE "$DETECTED_CLI" --version)"
  say "Dry test passed"
}

post_test() {
  ensure_dirs
  build_test_paths
  say "Post test: validating managed wrapper and compatibility links"
  failures=0

  OLD_IFS="$IFS"
  IFS='
'
  for path in $TEST_PATHS; do
    [ -n "$path" ] || continue
    run_single_version_test "$path" "$path" || failures=$((failures + 1))
    run_gui_like_test "$path" "$path" || failures=$((failures + 1))
  done
  IFS="$OLD_IFS"

  if [ "$failures" -ne 0 ]; then
    die "Post test failed with $failures failing checks"
  fi

  say "Post test passed"
}

run_state_file_test() {
  if [ -f "$STATE_FILE" ]; then
    say "state file ok: $STATE_FILE"
    return 0
  fi
  warn "state file missing: $STATE_FILE"
  return 1
}

run_realpath_test() {
  path="$1"
  label="$2"
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    warn "$label missing for realpath test: $path"
    return 1
  fi
  resolved="$(resolve_path "$path" 2>/dev/null || true)"
  if [ "$resolved" = "$PRIMARY_WRAPPER" ] || [ "$path" = "$PRIMARY_WRAPPER" ]; then
    say "$label target ok: ${resolved:-$path}"
    return 0
  fi
  warn "$label target mismatch: ${resolved:-unresolved}"
  return 1
}

matrix_test() {
  ensure_dirs
  build_test_paths
  say "Matrix test: exercising wrapper paths across multiple checks"
  failures=0

  dry_test || failures=$((failures + 1))
  run_state_file_test || failures=$((failures + 1))

  OLD_IFS="$IFS"
  IFS='
'
  for path in $TEST_PATHS; do
    [ -n "$path" ] || continue
    run_realpath_test "$path" "$path" || failures=$((failures + 1))
    run_single_version_test "$path" "$path" || failures=$((failures + 1))
    run_gui_like_test "$path" "$path" || failures=$((failures + 1))
  done
  IFS="$OLD_IFS"

  if [ "$failures" -ne 0 ]; then
    die "Matrix test failed with $failures failing checks"
  fi

  say "Matrix test passed"
}

remove_managed_link() {
  link_path="$1"
  [ -L "$link_path" ] || return 0
  target="$(resolve_path "$link_path" 2>/dev/null || true)"
  if [ "$target" = "$PRIMARY_WRAPPER" ] || [ "$target" = "$(resolve_path "$PRIMARY_WRAPPER" 2>/dev/null || true)" ]; then
    backup_file "$link_path"
    rm -f "$link_path"
    say "Removed compatibility link: $link_path"
  fi
}

uninstall_managed() {
  acquire_lock
  ensure_dirs

  if [ -e "$PRIMARY_WRAPPER" ] && is_ours "$PRIMARY_WRAPPER"; then
    backup_file "$PRIMARY_WRAPPER"
    rm -f "$PRIMARY_WRAPPER"
    say "Removed managed primary wrapper"
  else
    warn "Primary wrapper is absent or not managed by this script; leaving it untouched"
  fi

  remove_managed_link "$CLAUDE_COMPAT_WRAPPER"
  remove_managed_link "$CLAUDE_LOCAL_COMPAT_WRAPPER"
  remove_managed_link "$NPM_COMPAT_WRAPPER"
  remove_managed_link "$OPTIONAL_BUN_COMPAT_WRAPPER"

  rm -f "$STATE_FILE"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [install|repair|doctor|dry-test|post-test|matrix-test|uninstall|help]

Environment:
  ENABLE_BUN_COMPAT=1   Also maintain ~/.bun/bin/claude as a compatibility link

Notes on fallbacks:
  - Python 3 is optional. When available, it is used for richer path discovery and realpath resolution.
  - Without Python 3, the script falls back to shell-based detection for node, managed-file checks, and common Claude CLI locations.
  - Shell fallback is intentionally narrower: it prioritizes common global install locations and nearby inferred paths, but it does not perform the same deep recursive search or scoring quality as the Python-assisted path scan.
  - Runtime wrappers are designed to keep working without Python when a valid preferred node/cli path or common fallback path exists.

Commands:
  install      Install or refresh the managed Claude wrapper
  repair       Same as install
  doctor       Print current diagnosis and detected resources
  dry-test     Run non-invasive preflight checks without modifying files
  post-test    Validate managed wrapper and compat links, including GUI-like execution
  matrix-test  Run the broadest built-in validation matrix across paths, targets, state, and GUI-like execution
  uninstall    Remove only wrappers managed by this script
  help         Show this help text

Default command: install
EOF
}

main() {
  cmd="${1:-install}"
  case "$cmd" in
    install)
      install_or_repair
      ;;
    repair)
      install_or_repair
      ;;
    doctor)
      doctor
      ;;
    dry-test|--dry-test)
      dry_test
      ;;
    post-test|--post-test)
      post_test
      ;;
    matrix-test|--matrix-test)
      matrix_test
      ;;
    uninstall)
      uninstall_managed
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
