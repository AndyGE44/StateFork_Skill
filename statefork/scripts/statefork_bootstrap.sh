#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  statefork_bootstrap.sh <ssh-host>
  statefork_bootstrap.sh --local
  statefork_bootstrap.sh

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
    STATEFORK_INSTALL_ROOT="${STATEFORK_INSTALL_ROOT:-}" \
    STATEFORK_ROOT="${STATEFORK_ROOT:-}" \
    WAYPOINT_ROOT="${WAYPOINT_ROOT:-}" \
    STATEFORK_WORK_ROOT="${STATEFORK_WORK_ROOT:-}" \
    STATEFORK_REPO_URL="${STATEFORK_REPO_URL:-}" \
    WAYPOINT_REPO_URL="${WAYPOINT_REPO_URL:-}" \
    STATEFORK_REPO_FALLBACKS="${STATEFORK_REPO_FALLBACKS:-}" \
    WAYPOINT_REPO_FALLBACKS="${WAYPOINT_REPO_FALLBACKS:-}" \
    STATEFORK_CONFIG="${STATEFORK_CONFIG:-}" \
    bash -s <<'REMOTE'
# STATEFORK_BOOTSTRAP_PAYLOAD_BEGIN
set -euo pipefail

IN_STATEFORK_INSTALL_ROOT="${STATEFORK_INSTALL_ROOT:-}"
IN_STATEFORK_ROOT="${STATEFORK_ROOT:-}"
IN_WAYPOINT_ROOT="${WAYPOINT_ROOT:-}"
IN_STATEFORK_WORK_ROOT="${STATEFORK_WORK_ROOT:-}"
IN_STATEFORK_REPO_URL="${STATEFORK_REPO_URL:-}"
IN_WAYPOINT_REPO_URL="${WAYPOINT_REPO_URL:-}"
IN_STATEFORK_REPO_FALLBACKS="${STATEFORK_REPO_FALLBACKS:-}"
IN_WAYPOINT_REPO_FALLBACKS="${WAYPOINT_REPO_FALLBACKS:-}"

CONFIG_FILE="${STATEFORK_CONFIG:-$HOME/.statefork-agent.env}"
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
fi

STATEFORK_INSTALL_ROOT="${IN_STATEFORK_INSTALL_ROOT:-${STATEFORK_INSTALL_ROOT:-$HOME/statefork-agent}}"
STATEFORK_ROOT="${IN_STATEFORK_ROOT:-${STATEFORK_ROOT:-$STATEFORK_INSTALL_ROOT/StateFork}}"
WAYPOINT_ROOT="${IN_WAYPOINT_ROOT:-${WAYPOINT_ROOT:-$STATEFORK_INSTALL_ROOT/Waypoint}}"
STATEFORK_WORK_ROOT="${IN_STATEFORK_WORK_ROOT:-${STATEFORK_WORK_ROOT:-$STATEFORK_INSTALL_ROOT/work}}"

STATEFORK_REPO_URL="${IN_STATEFORK_REPO_URL:-${STATEFORK_REPO_URL:-https://github.com/AndyGE44/Andy_StateFork.git}}"
WAYPOINT_REPO_URL="${IN_WAYPOINT_REPO_URL:-${WAYPOINT_REPO_URL:-https://github.com/AndyGE44/Andy_Waypoint.git}}"
STATEFORK_REPO_FALLBACKS="${IN_STATEFORK_REPO_FALLBACKS:-${STATEFORK_REPO_FALLBACKS:-https://github.com/Alex-XJK/StateFork.git}}"
WAYPOINT_REPO_FALLBACKS="${IN_WAYPOINT_REPO_FALLBACKS:-${WAYPOINT_REPO_FALLBACKS:-https://github.com/Alex-XJK/waypoint.git}}"

failures=0
pass() { printf '[OK] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1"; failures=$((failures + 1)); }

if [ "$(uname -s)" != "Linux" ]; then
  fail "StateFork requires Linux; this host reports $(uname -s)"
fi

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
  local name="$1"
  local dir="$2"
  local primary="$3"
  local fallbacks="$4"
  local urls url

  if [ -d "$dir/.git" ]; then
    pass "$name repo exists: $dir"
    if [ -z "$(git -C "$dir" status --porcelain)" ]; then
      if git -C "$dir" pull --ff-only; then
        pass "$name repo updated"
      else
        warn "$name pull failed; continuing with existing checkout"
      fi
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
    [ -n "$url" ] || continue
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

shell_quote() {
  printf "'"
  printf "%s" "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

write_export() {
  printf 'export %s=' "$1"
  shell_quote "$2"
  printf '\n'
}

{
  printf '# StateFork agent config generated by statefork_bootstrap.sh\n'
  write_export STATEFORK_ROOT "$STATEFORK_ROOT"
  write_export WAYPOINT_ROOT "$WAYPOINT_ROOT"
  write_export STATEFORK_PYTHON "$STATEFORK_PYTHON"
  write_export STATEFORK_WORK_ROOT "$STATEFORK_WORK_ROOT"
  write_export STATEFORK_REPO_URL "$STATEFORK_REPO_URL"
  write_export WAYPOINT_REPO_URL "$WAYPOINT_REPO_URL"
  write_export STATEFORK_REPO_FALLBACKS "$STATEFORK_REPO_FALLBACKS"
  write_export WAYPOINT_REPO_FALLBACKS "$WAYPOINT_REPO_FALLBACKS"
} > "$CONFIG_FILE"
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
# STATEFORK_BOOTSTRAP_PAYLOAD_END
REMOTE
}

if [ -n "$HOST" ]; then
  remote_prefix=""
  for var in \
    STATEFORK_INSTALL_ROOT \
    STATEFORK_ROOT \
    WAYPOINT_ROOT \
    STATEFORK_WORK_ROOT \
    STATEFORK_REPO_URL \
    WAYPOINT_REPO_URL \
    STATEFORK_REPO_FALLBACKS \
    WAYPOINT_REPO_FALLBACKS \
    STATEFORK_CONFIG
  do
    value="${!var:-}"
    if [ -n "$value" ]; then
      remote_prefix="${remote_prefix}${var}=$(shell_quote "$value") "
    fi
  done
  ssh "$HOST" "${remote_prefix}bash -s" < <(sed -n '/^# STATEFORK_BOOTSTRAP_PAYLOAD_BEGIN$/,/^# STATEFORK_BOOTSTRAP_PAYLOAD_END$/p' "$0" | sed '1d;$d')
else
  run_payload_local
fi
