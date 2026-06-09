#!/usr/bin/env bash
set -uo pipefail

usage() {
  cat <<'EOF'
Usage:
  statefork_probe.sh <ssh-host>
  statefork_probe.sh --local
  statefork_probe.sh

When no argument is provided, the script reads ~/.statefork-skill.env.
Create that file with statefork_configure.sh, or set STATEFORK_HOST.
EOF
}

LOCAL_CONFIG="${STATEFORK_SKILL_CONFIG:-$HOME/.statefork-skill.env}"
if [ -f "$LOCAL_CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$LOCAL_CONFIG"
fi

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 1 ]; then
  usage
  exit 2
fi

HOST=""
case "${1:-}" in
  --local)
    STATEFORK_LOCAL=1
    ;;
  "")
    if [ "${STATEFORK_LOCAL:-0}" = "1" ]; then
      HOST=""
    elif [ -n "${STATEFORK_HOST:-}" ]; then
      HOST="$STATEFORK_HOST"
    else
      cat <<EOF
[FAIL] No StateFork Linux target configured.

Configure one of:
  $(dirname "$0")/statefork_configure.sh --host user@linux-vm
  $(dirname "$0")/statefork_configure.sh --local

Or run directly:
  $0 <ssh-host>
  $0 --local
EOF
      exit 2
    fi
    ;;
  *)
    HOST="$1"
    ;;
esac

shell_quote() {
  printf "'"
  printf "%s" "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

run_payload_local() {
  env \
    STATEFORK_ROOT="${STATEFORK_ROOT:-}" \
    WAYPOINT_ROOT="${WAYPOINT_ROOT:-}" \
    STATEFORK_PYTHON="${STATEFORK_PYTHON:-}" \
    STATEFORK_CONFIG="${STATEFORK_CONFIG:-}" \
    bash -s <<'REMOTE'
# STATEFORK_PROBE_PAYLOAD_BEGIN
set -uo pipefail

IN_STATEFORK_ROOT="${STATEFORK_ROOT:-}"
IN_WAYPOINT_ROOT="${WAYPOINT_ROOT:-}"
IN_STATEFORK_PYTHON="${STATEFORK_PYTHON:-}"

CONFIG_FILE="${STATEFORK_CONFIG:-$HOME/.statefork-agent.env}"
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
fi

STATEFORK_INSTALL_ROOT="${STATEFORK_INSTALL_ROOT:-$HOME/statefork-agent}"
STATEFORK_ROOT="${IN_STATEFORK_ROOT:-${STATEFORK_ROOT:-$STATEFORK_INSTALL_ROOT/StateFork}}"
WAYPOINT_ROOT="${IN_WAYPOINT_ROOT:-${WAYPOINT_ROOT:-$STATEFORK_INSTALL_ROOT/Waypoint}}"
STATEFORK_PYTHON="${IN_STATEFORK_PYTHON:-${STATEFORK_PYTHON:-}}"

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

printf 'StateFork probe host=%s\n' "$(hostname)"
printf 'STATEFORK_CONFIG=%s\n' "$CONFIG_FILE"
printf 'STATEFORK_ROOT=%s\n' "$STATEFORK_ROOT"
printf 'WAYPOINT_ROOT=%s\n' "$WAYPOINT_ROOT"

if [ "$(uname -s)" = "Linux" ]; then
  pass "Linux host confirmed"
else
  fail "StateFork requires Linux; this host reports $(uname -s)"
fi

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

for cmd in python3 sudo criu go buildah docker podman; do
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
# STATEFORK_PROBE_PAYLOAD_END
REMOTE
}

if [ -n "$HOST" ]; then
  remote_prefix=""
  for var in STATEFORK_ROOT WAYPOINT_ROOT STATEFORK_PYTHON STATEFORK_CONFIG; do
    value="${!var:-}"
    if [ -n "$value" ]; then
      remote_prefix="${remote_prefix}${var}=$(shell_quote "$value") "
    fi
  done
  ssh "$HOST" "${remote_prefix}bash -s" < <(sed -n '/^# STATEFORK_PROBE_PAYLOAD_BEGIN$/,/^# STATEFORK_PROBE_PAYLOAD_END$/p' "$0" | sed '1d;$d')
else
  run_payload_local
fi
