#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-${STATEFORK_HOST:-sf-exp}}"
if [ "${HOST}" = "--local" ]; then
  HOST=""
fi

STATEFORK_INSTALL_ROOT="${STATEFORK_INSTALL_ROOT:-}"
STATEFORK_ROOT="${STATEFORK_ROOT:-}"
WAYPOINT_ROOT="${WAYPOINT_ROOT:-}"
STATEFORK_WORK_ROOT="${STATEFORK_WORK_ROOT:-}"
STATEFORK_REPO_URL="${STATEFORK_REPO_URL:-}"
WAYPOINT_REPO_URL="${WAYPOINT_REPO_URL:-}"

run_remote() {
  bash -s <<'REMOTE'
set -euo pipefail

CONFIG_FILE="${STATEFORK_CONFIG:-$HOME/.statefork-agent.env}"
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
fi

STATEFORK_INSTALL_ROOT="${STATEFORK_INSTALL_ROOT:-$HOME/statefork-agent}"
STATEFORK_ROOT="${STATEFORK_ROOT:-$STATEFORK_INSTALL_ROOT/Andy_StateFork}"
WAYPOINT_ROOT="${WAYPOINT_ROOT:-$STATEFORK_INSTALL_ROOT/Andy_Waypoint}"
STATEFORK_WORK_ROOT="${STATEFORK_WORK_ROOT:-$STATEFORK_INSTALL_ROOT/work}"

STATEFORK_REPO_URL="${STATEFORK_REPO_URL:-https://github.com/AndyGE44/Andy_StateFork.git}"
WAYPOINT_REPO_URL="${WAYPOINT_REPO_URL:-https://github.com/AndyGE44/Andy_Waypoint.git}"
STATEFORK_REPO_FALLBACKS="${STATEFORK_REPO_FALLBACKS:-https://github.com/Alex-XJK/StateFork.git}"
WAYPOINT_REPO_FALLBACKS="${WAYPOINT_REPO_FALLBACKS:-https://github.com/AndyGE44/Andy_checkpoint-lite.git https://github.com/Alex-XJK/waypoint.git}"

failures=0
pass() { printf '[OK] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1"; failures=$((failures + 1)); }

need_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "command available: $1 ($(command -v "$1"))"
  else
    fail "missing command: $1"
  fi
}

need_cmd git
need_cmd python3
need_cmd go
need_cmd sudo
need_cmd criu

if ! python3 -m venv --help >/dev/null 2>&1; then
  fail "python3 venv support is missing"
fi

if grep -qw overlay /proc/filesystems 2>/dev/null; then
  pass "OverlayFS listed in /proc/filesystems"
else
  fail "OverlayFS not listed in /proc/filesystems"
fi

if [ "$failures" -gt 0 ]; then
  cat <<'MSG'
[HINT] Install missing system dependencies first. On Ubuntu-like systems this is often:
  sudo apt-get update
  sudo apt-get install -y git python3 python3-venv python3-pip golang-go criu
MSG
  exit "$failures"
fi

mkdir -p "$STATEFORK_INSTALL_ROOT" "$STATEFORK_WORK_ROOT"

clone_or_update() {
  name="$1"
  dir="$2"
  primary="$3"
  fallbacks="$4"

  if [ -d "$dir/.git" ]; then
    pass "$name repo exists: $dir"
    if [ -z "$(git -C "$dir" status --porcelain)" ]; then
      git -C "$dir" pull --ff-only
      pass "$name repo updated"
    else
      warn "$name repo has local changes; skipping pull: $dir"
    fi
    return
  fi

  if [ -e "$dir" ]; then
    fail "$name path exists but is not a git repo: $dir"
    return
  fi

  urls="$primary $fallbacks"
  for url in $urls; do
    printf '[INFO] cloning %s from %s\n' "$name" "$url"
    if git clone "$url" "$dir"; then
      pass "$name cloned to $dir"
      return
    fi
    warn "clone failed: $url"
    rm -rf "$dir"
  done

  fail "could not clone $name"
}

clone_or_update "StateFork" "$STATEFORK_ROOT" "$STATEFORK_REPO_URL" "$STATEFORK_REPO_FALLBACKS"
clone_or_update "Waypoint" "$WAYPOINT_ROOT" "$WAYPOINT_REPO_URL" "$WAYPOINT_REPO_FALLBACKS"

if [ ! -f "$WAYPOINT_ROOT/cmd/waypoint/main.go" ]; then
  fail "Waypoint source layout not found at $WAYPOINT_ROOT"
fi
if [ ! -f "$WAYPOINT_ROOT/cmd/bash-init/main.go" ]; then
  fail "Waypoint bash-init source layout not found at $WAYPOINT_ROOT"
fi
if [ ! -f "$STATEFORK_ROOT/requirements.txt" ]; then
  fail "StateFork requirements.txt not found at $STATEFORK_ROOT"
fi
if [ "$failures" -gt 0 ]; then
  exit "$failures"
fi

(cd "$WAYPOINT_ROOT" && go build -o waypoint cmd/waypoint/main.go && go build -o bash_init cmd/bash-init/main.go)
pass "Waypoint binaries built"

rel_waypoint="$(python3 -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$WAYPOINT_ROOT/waypoint" "$STATEFORK_ROOT")"
rel_bash_init="$(python3 -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$WAYPOINT_ROOT/bash_init" "$STATEFORK_ROOT")"
ln -sfn "$rel_waypoint" "$STATEFORK_ROOT/waypoint"
ln -sfn "$rel_bash_init" "$STATEFORK_ROOT/bash_init"
pass "StateFork Waypoint symlinks configured"

if [ ! -x "$STATEFORK_ROOT/.venv/bin/python" ]; then
  python3 -m venv "$STATEFORK_ROOT/.venv"
  pass "StateFork venv created"
else
  pass "StateFork venv exists"
fi

"$STATEFORK_ROOT/.venv/bin/python" -m pip install -r "$STATEFORK_ROOT/requirements.txt" paramiko
STATEFORK_PYTHON="$STATEFORK_ROOT/.venv/bin/python"
pass "StateFork Python dependencies installed"

cat > "$CONFIG_FILE" <<EOF
export STATEFORK_ROOT="$STATEFORK_ROOT"
export WAYPOINT_ROOT="$WAYPOINT_ROOT"
export STATEFORK_PYTHON="$STATEFORK_PYTHON"
export STATEFORK_WORK_ROOT="$STATEFORK_WORK_ROOT"
export STATEFORK_REPO_URL="$STATEFORK_REPO_URL"
export WAYPOINT_REPO_URL="$WAYPOINT_REPO_URL"
EOF
pass "configuration written: $CONFIG_FILE"

(cd "$STATEFORK_ROOT" && "$STATEFORK_PYTHON" - <<'PY'
from controller import create_env_manager
from decider import AlwaysTrueDecider
print("StateFork imports OK", create_env_manager, AlwaysTrueDecider)
PY
)
"$STATEFORK_ROOT/waypoint" version
pass "bootstrap completed"

printf 'STATEFORK_ROOT=%s\n' "$STATEFORK_ROOT"
printf 'WAYPOINT_ROOT=%s\n' "$WAYPOINT_ROOT"
printf 'STATEFORK_PYTHON=%s\n' "$STATEFORK_PYTHON"
printf 'STATEFORK_WORK_ROOT=%s\n' "$STATEFORK_WORK_ROOT"
REMOTE
}

if [ -n "$HOST" ]; then
  ssh "$HOST" \
    "STATEFORK_INSTALL_ROOT='$STATEFORK_INSTALL_ROOT' STATEFORK_ROOT='$STATEFORK_ROOT' WAYPOINT_ROOT='$WAYPOINT_ROOT' STATEFORK_WORK_ROOT='$STATEFORK_WORK_ROOT' STATEFORK_REPO_URL='$STATEFORK_REPO_URL' WAYPOINT_REPO_URL='$WAYPOINT_REPO_URL' bash -s" <<'REMOTE'
set -euo pipefail

CONFIG_FILE="${STATEFORK_CONFIG:-$HOME/.statefork-agent.env}"
if [ -f "$CONFIG_FILE" ]; then
  . "$CONFIG_FILE"
fi

STATEFORK_INSTALL_ROOT="${STATEFORK_INSTALL_ROOT:-$HOME/statefork-agent}"
STATEFORK_ROOT="${STATEFORK_ROOT:-$STATEFORK_INSTALL_ROOT/Andy_StateFork}"
WAYPOINT_ROOT="${WAYPOINT_ROOT:-$STATEFORK_INSTALL_ROOT/Andy_Waypoint}"
STATEFORK_WORK_ROOT="${STATEFORK_WORK_ROOT:-$STATEFORK_INSTALL_ROOT/work}"

STATEFORK_REPO_URL="${STATEFORK_REPO_URL:-https://github.com/AndyGE44/Andy_StateFork.git}"
WAYPOINT_REPO_URL="${WAYPOINT_REPO_URL:-https://github.com/AndyGE44/Andy_Waypoint.git}"
STATEFORK_REPO_FALLBACKS="${STATEFORK_REPO_FALLBACKS:-https://github.com/Alex-XJK/StateFork.git}"
WAYPOINT_REPO_FALLBACKS="${WAYPOINT_REPO_FALLBACKS:-https://github.com/AndyGE44/Andy_checkpoint-lite.git https://github.com/Alex-XJK/waypoint.git}"

failures=0
pass() { printf '[OK] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1"; failures=$((failures + 1)); }

need_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "command available: $1 ($(command -v "$1"))"
  else
    fail "missing command: $1"
  fi
}

need_cmd git
need_cmd python3
need_cmd go
need_cmd sudo
need_cmd criu

if ! python3 -m venv --help >/dev/null 2>&1; then
  fail "python3 venv support is missing"
fi

if grep -qw overlay /proc/filesystems 2>/dev/null; then
  pass "OverlayFS listed in /proc/filesystems"
else
  fail "OverlayFS not listed in /proc/filesystems"
fi

if [ "$failures" -gt 0 ]; then
  cat <<'MSG'
[HINT] Install missing system dependencies first. On Ubuntu-like systems this is often:
  sudo apt-get update
  sudo apt-get install -y git python3 python3-venv python3-pip golang-go criu
MSG
  exit "$failures"
fi

mkdir -p "$STATEFORK_INSTALL_ROOT" "$STATEFORK_WORK_ROOT"

clone_or_update() {
  name="$1"
  dir="$2"
  primary="$3"
  fallbacks="$4"

  if [ -d "$dir/.git" ]; then
    pass "$name repo exists: $dir"
    if [ -z "$(git -C "$dir" status --porcelain)" ]; then
      git -C "$dir" pull --ff-only
      pass "$name repo updated"
    else
      warn "$name repo has local changes; skipping pull: $dir"
    fi
    return
  fi

  if [ -e "$dir" ]; then
    fail "$name path exists but is not a git repo: $dir"
    return
  fi

  urls="$primary $fallbacks"
  for url in $urls; do
    printf '[INFO] cloning %s from %s\n' "$name" "$url"
    if git clone "$url" "$dir"; then
      pass "$name cloned to $dir"
      return
    fi
    warn "clone failed: $url"
    rm -rf "$dir"
  done

  fail "could not clone $name"
}

clone_or_update "StateFork" "$STATEFORK_ROOT" "$STATEFORK_REPO_URL" "$STATEFORK_REPO_FALLBACKS"
clone_or_update "Waypoint" "$WAYPOINT_ROOT" "$WAYPOINT_REPO_URL" "$WAYPOINT_REPO_FALLBACKS"

if [ ! -f "$WAYPOINT_ROOT/cmd/waypoint/main.go" ]; then
  fail "Waypoint source layout not found at $WAYPOINT_ROOT"
fi
if [ ! -f "$WAYPOINT_ROOT/cmd/bash-init/main.go" ]; then
  fail "Waypoint bash-init source layout not found at $WAYPOINT_ROOT"
fi
if [ ! -f "$STATEFORK_ROOT/requirements.txt" ]; then
  fail "StateFork requirements.txt not found at $STATEFORK_ROOT"
fi
if [ "$failures" -gt 0 ]; then
  exit "$failures"
fi

(cd "$WAYPOINT_ROOT" && go build -o waypoint cmd/waypoint/main.go && go build -o bash_init cmd/bash-init/main.go)
pass "Waypoint binaries built"

rel_waypoint="$(python3 -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$WAYPOINT_ROOT/waypoint" "$STATEFORK_ROOT")"
rel_bash_init="$(python3 -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$WAYPOINT_ROOT/bash_init" "$STATEFORK_ROOT")"
ln -sfn "$rel_waypoint" "$STATEFORK_ROOT/waypoint"
ln -sfn "$rel_bash_init" "$STATEFORK_ROOT/bash_init"
pass "StateFork Waypoint symlinks configured"

if [ ! -x "$STATEFORK_ROOT/.venv/bin/python" ]; then
  python3 -m venv "$STATEFORK_ROOT/.venv"
  pass "StateFork venv created"
else
  pass "StateFork venv exists"
fi

"$STATEFORK_ROOT/.venv/bin/python" -m pip install -r "$STATEFORK_ROOT/requirements.txt" paramiko
STATEFORK_PYTHON="$STATEFORK_ROOT/.venv/bin/python"
pass "StateFork Python dependencies installed"

cat > "$CONFIG_FILE" <<EOF
export STATEFORK_ROOT="$STATEFORK_ROOT"
export WAYPOINT_ROOT="$WAYPOINT_ROOT"
export STATEFORK_PYTHON="$STATEFORK_PYTHON"
export STATEFORK_WORK_ROOT="$STATEFORK_WORK_ROOT"
export STATEFORK_REPO_URL="$STATEFORK_REPO_URL"
export WAYPOINT_REPO_URL="$WAYPOINT_REPO_URL"
EOF
pass "configuration written: $CONFIG_FILE"

(cd "$STATEFORK_ROOT" && "$STATEFORK_PYTHON" - <<'PY'
from controller import create_env_manager
from decider import AlwaysTrueDecider
print("StateFork imports OK", create_env_manager, AlwaysTrueDecider)
PY
)
"$STATEFORK_ROOT/waypoint" version
pass "bootstrap completed"

printf 'STATEFORK_ROOT=%s\n' "$STATEFORK_ROOT"
printf 'WAYPOINT_ROOT=%s\n' "$WAYPOINT_ROOT"
printf 'STATEFORK_PYTHON=%s\n' "$STATEFORK_PYTHON"
printf 'STATEFORK_WORK_ROOT=%s\n' "$STATEFORK_WORK_ROOT"
REMOTE
else
  run_remote
fi
