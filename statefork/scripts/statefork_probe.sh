#!/usr/bin/env bash
set -uo pipefail

HOST="${1:-${STATEFORK_HOST:-sf-exp}}"
if [ "${HOST}" = "--local" ]; then
  HOST=""
fi
STATEFORK_ROOT="${STATEFORK_ROOT:-}"
WAYPOINT_ROOT="${WAYPOINT_ROOT:-}"
STATEFORK_PYTHON="${STATEFORK_PYTHON:-}"

run_probe() {
bash -s <<'REMOTE'
set -uo pipefail

failures=0

pass() { printf '[OK] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1"; failures=$((failures + 1)); }

check_dir() {
  if [ -d "$1" ]; then
    pass "directory exists: $1"
  else
    fail "missing directory: $1"
  fi
}

check_exe() {
  if [ -x "$1" ]; then
    pass "executable exists: $1"
  else
    fail "missing executable: $1"
  fi
}

CONFIG_FILE="${STATEFORK_CONFIG:-$HOME/.statefork-agent.env}"
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
fi

if [ -z "${STATEFORK_ROOT:-}" ]; then
  if [ -d /users/alexxjk/Andy_StateFork ]; then
    STATEFORK_ROOT="/users/alexxjk/Andy_StateFork"
  else
    STATEFORK_ROOT="$HOME/statefork-agent/Andy_StateFork"
  fi
fi
if [ -z "${WAYPOINT_ROOT:-}" ]; then
  if [ -d /users/alexxjk/Andy_Waypoint ]; then
    WAYPOINT_ROOT="/users/alexxjk/Andy_Waypoint"
  else
    WAYPOINT_ROOT="$HOME/statefork-agent/Andy_Waypoint"
  fi
fi

printf 'StateFork probe host=%s\n' "$(hostname)"
printf 'STATEFORK_ROOT=%s\n' "$STATEFORK_ROOT"
printf 'WAYPOINT_ROOT=%s\n' "$WAYPOINT_ROOT"

if [ -z "${STATEFORK_PYTHON:-}" ]; then
  if [ -x "$STATEFORK_ROOT/.venv/bin/python" ]; then
    STATEFORK_PYTHON="$STATEFORK_ROOT/.venv/bin/python"
  else
    STATEFORK_PYTHON="python3"
  fi
fi

printf 'STATEFORK_PYTHON=%s\n' "$STATEFORK_PYTHON"

check_dir "$STATEFORK_ROOT"
check_dir "$WAYPOINT_ROOT"

if command -v git >/dev/null 2>&1; then
  sf_rev="$(git -C "$STATEFORK_ROOT" rev-parse --short HEAD 2>/dev/null || true)"
  wp_rev="$(git -C "$WAYPOINT_ROOT" rev-parse --short HEAD 2>/dev/null || true)"
  [ -n "$sf_rev" ] && pass "StateFork git rev: $sf_rev" || warn "StateFork git rev unavailable"
  [ -n "$wp_rev" ] && pass "Waypoint git rev: $wp_rev" || warn "Waypoint git rev unavailable"
else
  warn "git not found"
fi

check_exe "$STATEFORK_ROOT/waypoint"
check_exe "$STATEFORK_ROOT/bash_init"
check_exe "$WAYPOINT_ROOT/waypoint"
check_exe "$WAYPOINT_ROOT/bash_init"

if [ -x "$STATEFORK_ROOT/waypoint" ]; then
  "$STATEFORK_ROOT/waypoint" version 2>/dev/null || warn "StateFork waypoint version command failed"
fi

if [ -x "$WAYPOINT_ROOT/waypoint" ]; then
  "$WAYPOINT_ROOT/waypoint" version 2>/dev/null || warn "Waypoint version command failed"
fi

for cmd in python3 go sudo criu buildah docker podman; do
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "command available: $cmd ($(command -v "$cmd"))"
  else
    case "$cmd" in
      python3|sudo|criu) fail "required command unavailable: $cmd" ;;
      *) warn "optional command unavailable: $cmd" ;;
    esac
  fi
done

if grep -qw overlay /proc/filesystems 2>/dev/null; then
  pass "OverlayFS listed in /proc/filesystems"
else
  fail "OverlayFS not listed in /proc/filesystems"
fi

if command -v "$STATEFORK_PYTHON" >/dev/null 2>&1 || [ -x "$STATEFORK_PYTHON" ]; then
  pass "StateFork Python candidate available: $STATEFORK_PYTHON"
else
  fail "StateFork Python candidate unavailable: $STATEFORK_PYTHON"
fi

if { command -v "$STATEFORK_PYTHON" >/dev/null 2>&1 || [ -x "$STATEFORK_PYTHON" ]; } && [ -d "$STATEFORK_ROOT" ]; then
  if (cd "$STATEFORK_ROOT" && "$STATEFORK_PYTHON" - <<'PY'
from controller import create_env_manager
from decider import AlwaysTrueDecider, AlwaysFalseDecider, RandomDecider, ThresholdDecider
print("StateFork imports OK")
print(create_env_manager)
print(AlwaysTrueDecider, AlwaysFalseDecider, RandomDecider, ThresholdDecider)
PY
  ); then
    pass "StateFork Python imports"
  else
    fail "StateFork Python imports failed"
    warn "try: cd $STATEFORK_ROOT && python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt paramiko"
    warn "then rerun with STATEFORK_PYTHON=$STATEFORK_ROOT/.venv/bin/python"
  fi
fi

if command -v sudo >/dev/null 2>&1; then
  if sudo -n true >/dev/null 2>&1; then
    pass "passwordless sudo available"
  else
    warn "passwordless sudo unavailable; interactive sudo may be required"
  fi
fi

if [ "$failures" -eq 0 ]; then
  pass "probe completed without hard failures"
else
  printf '[FAIL] probe completed with %s hard failure(s)\n' "$failures"
fi

exit "$failures"
REMOTE
}

if [ -n "$HOST" ]; then
  ssh "$HOST" "STATEFORK_ROOT='$STATEFORK_ROOT' WAYPOINT_ROOT='$WAYPOINT_ROOT' STATEFORK_PYTHON='$STATEFORK_PYTHON' bash -s" <<'REMOTE'
set -uo pipefail

failures=0

pass() { printf '[OK] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1"; failures=$((failures + 1)); }

check_dir() {
  if [ -d "$1" ]; then
    pass "directory exists: $1"
  else
    fail "missing directory: $1"
  fi
}

check_exe() {
  if [ -x "$1" ]; then
    pass "executable exists: $1"
  else
    fail "missing executable: $1"
  fi
}

CONFIG_FILE="${STATEFORK_CONFIG:-$HOME/.statefork-agent.env}"
if [ -f "$CONFIG_FILE" ]; then
  . "$CONFIG_FILE"
fi

if [ -z "${STATEFORK_ROOT:-}" ]; then
  if [ -d /users/alexxjk/Andy_StateFork ]; then
    STATEFORK_ROOT="/users/alexxjk/Andy_StateFork"
  else
    STATEFORK_ROOT="$HOME/statefork-agent/Andy_StateFork"
  fi
fi
if [ -z "${WAYPOINT_ROOT:-}" ]; then
  if [ -d /users/alexxjk/Andy_Waypoint ]; then
    WAYPOINT_ROOT="/users/alexxjk/Andy_Waypoint"
  else
    WAYPOINT_ROOT="$HOME/statefork-agent/Andy_Waypoint"
  fi
fi

printf 'StateFork probe host=%s\n' "$(hostname)"
printf 'STATEFORK_ROOT=%s\n' "$STATEFORK_ROOT"
printf 'WAYPOINT_ROOT=%s\n' "$WAYPOINT_ROOT"

if [ -z "${STATEFORK_PYTHON:-}" ]; then
  if [ -x "$STATEFORK_ROOT/.venv/bin/python" ]; then
    STATEFORK_PYTHON="$STATEFORK_ROOT/.venv/bin/python"
  else
    STATEFORK_PYTHON="python3"
  fi
fi

printf 'STATEFORK_PYTHON=%s\n' "$STATEFORK_PYTHON"

check_dir "$STATEFORK_ROOT"
check_dir "$WAYPOINT_ROOT"

if command -v git >/dev/null 2>&1; then
  sf_rev="$(git -C "$STATEFORK_ROOT" rev-parse --short HEAD 2>/dev/null || true)"
  wp_rev="$(git -C "$WAYPOINT_ROOT" rev-parse --short HEAD 2>/dev/null || true)"
  [ -n "$sf_rev" ] && pass "StateFork git rev: $sf_rev" || warn "StateFork git rev unavailable"
  [ -n "$wp_rev" ] && pass "Waypoint git rev: $wp_rev" || warn "Waypoint git rev unavailable"
else
  warn "git not found"
fi

check_exe "$STATEFORK_ROOT/waypoint"
check_exe "$STATEFORK_ROOT/bash_init"
check_exe "$WAYPOINT_ROOT/waypoint"
check_exe "$WAYPOINT_ROOT/bash_init"

if [ -x "$STATEFORK_ROOT/waypoint" ]; then
  "$STATEFORK_ROOT/waypoint" version 2>/dev/null || warn "StateFork waypoint version command failed"
fi

if [ -x "$WAYPOINT_ROOT/waypoint" ]; then
  "$WAYPOINT_ROOT/waypoint" version 2>/dev/null || warn "Waypoint version command failed"
fi

for cmd in python3 go sudo criu buildah docker podman; do
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "command available: $cmd ($(command -v "$cmd"))"
  else
    case "$cmd" in
      python3|sudo|criu) fail "required command unavailable: $cmd" ;;
      *) warn "optional command unavailable: $cmd" ;;
    esac
  fi
done

if grep -qw overlay /proc/filesystems 2>/dev/null; then
  pass "OverlayFS listed in /proc/filesystems"
else
  fail "OverlayFS not listed in /proc/filesystems"
fi

if command -v "$STATEFORK_PYTHON" >/dev/null 2>&1 || [ -x "$STATEFORK_PYTHON" ]; then
  pass "StateFork Python candidate available: $STATEFORK_PYTHON"
else
  fail "StateFork Python candidate unavailable: $STATEFORK_PYTHON"
fi

if { command -v "$STATEFORK_PYTHON" >/dev/null 2>&1 || [ -x "$STATEFORK_PYTHON" ]; } && [ -d "$STATEFORK_ROOT" ]; then
  if (cd "$STATEFORK_ROOT" && "$STATEFORK_PYTHON" - <<'PY'
from controller import create_env_manager
from decider import AlwaysTrueDecider, AlwaysFalseDecider, RandomDecider, ThresholdDecider
print("StateFork imports OK")
print(create_env_manager)
print(AlwaysTrueDecider, AlwaysFalseDecider, RandomDecider, ThresholdDecider)
PY
  ); then
    pass "StateFork Python imports"
  else
    fail "StateFork Python imports failed"
    warn "try: cd $STATEFORK_ROOT && python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt paramiko"
    warn "then rerun with STATEFORK_PYTHON=$STATEFORK_ROOT/.venv/bin/python"
  fi
fi

if command -v sudo >/dev/null 2>&1; then
  if sudo -n true >/dev/null 2>&1; then
    pass "passwordless sudo available"
  else
    warn "passwordless sudo unavailable; interactive sudo may be required"
  fi
fi

if [ "$failures" -eq 0 ]; then
  pass "probe completed without hard failures"
else
  printf '[FAIL] probe completed with %s hard failure(s)\n' "$failures"
fi

exit "$failures"
REMOTE
else
  STATEFORK_ROOT="$STATEFORK_ROOT" WAYPOINT_ROOT="$WAYPOINT_ROOT" STATEFORK_PYTHON="$STATEFORK_PYTHON" run_probe
fi
