# Bootstrap And Setup

Use this when StateFork has not already been configured on the user's Linux VM or local Linux environment.

## User Input Needed

The user only needs to provide one of:

- an SSH target, such as `sf-exp`, `ubuntu@1.2.3.4`, or a configured SSH alias
- confirmation that the current machine is already Linux and should be used directly

Do not require the user to manually clone repos or write config before trying the bootstrap.

## Bootstrap Command

Remote VM:

```bash
/path/to/skill/scripts/statefork_bootstrap.sh <ssh-host>
```

Local Linux:

```bash
/path/to/skill/scripts/statefork_bootstrap.sh --local
```

The bootstrap script:

1. Checks for Linux requirements: `git`, `python3`, `python3 -m venv`, `go`, `sudo`, `criu`, and OverlayFS.
2. Clones or updates StateFork and Waypoint.
3. Builds Waypoint binaries: `waypoint` and `bash_init`.
4. Creates `waypoint` and `bash_init` symlinks in the StateFork root.
5. Creates a StateFork Python venv and installs `requirements.txt` plus `paramiko`.
6. Writes `~/.statefork-agent.env`.
7. Runs a basic import/version smoke test.

## Configuration

The generated config looks like:

```bash
export STATEFORK_ROOT="$HOME/statefork-agent/Andy_StateFork"
export WAYPOINT_ROOT="$HOME/statefork-agent/Andy_Waypoint"
export STATEFORK_PYTHON="$HOME/statefork-agent/Andy_StateFork/.venv/bin/python"
export STATEFORK_WORK_ROOT="$HOME/statefork-agent/work"
export STATEFORK_REPO_URL="https://github.com/AndyGE44/Andy_StateFork.git"
export WAYPOINT_REPO_URL="https://github.com/AndyGE44/Andy_Waypoint.git"
```

Override defaults before running bootstrap when needed:

```bash
STATEFORK_INSTALL_ROOT=/opt/statefork-agent \
STATEFORK_REPO_URL=https://github.com/<owner>/<statefork-repo>.git \
WAYPOINT_REPO_URL=https://github.com/<owner>/<waypoint-repo>.git \
/path/to/skill/scripts/statefork_bootstrap.sh <ssh-host>
```

If the Waypoint repo has not yet been renamed on GitHub, the bootstrap script falls back to `Andy_checkpoint-lite` and then `Alex-XJK/waypoint`.

## After Bootstrap

Run:

```bash
/path/to/skill/scripts/statefork_probe.sh <ssh-host>
```

Then use project mode. Workspace roots should default to `$STATEFORK_WORK_ROOT`.

## Safety

The bootstrap script does not install OS packages by default. If commands such as `go`, `criu`, or `python3 -m venv` are missing, it prints an install hint and stops. Installing system packages should be explicit because it changes the user's VM.
