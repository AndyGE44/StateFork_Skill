# Bootstrap And Setup

Use this when StateFork has not already been configured on the user's Linux VM or local Linux environment.

## Installer Boundary

Installing the skill only copies the skill files. The installer does not execute this repo's scripts and cannot reliably prompt for an SSH target during installation.

Configuration happens on first use:

1. Check whether `~/.statefork-skill.env` exists on the machine running Codex.
2. If it exists, use it.
3. If it does not exist, ask the user for an SSH target such as `user@linux-vm`, or ask them to confirm local Linux.
4. If the user wants to configure later, tell them to run `scripts/statefork_configure.sh` later or create `~/.statefork-skill.env` manually.

## Local Skill Config

Recommended:

```bash
/path/to/skill/scripts/statefork_configure.sh --host user@linux-vm
```

Or for local Linux:

```bash
/path/to/skill/scripts/statefork_configure.sh --local
```

This writes `~/.statefork-skill.env` on the machine running Codex. A remote VM config normally needs only:

```bash
export STATEFORK_HOST='user@linux-vm'
```

Optional Linux-side overrides can also be placed there:

```bash
export STATEFORK_INSTALL_ROOT='/opt/statefork-agent'
export STATEFORK_ROOT='/opt/statefork-agent/StateFork'
export WAYPOINT_ROOT='/opt/statefork-agent/Waypoint'
export STATEFORK_WORK_ROOT='/opt/statefork-agent/work'
export STATEFORK_REPO_URL='https://github.com/<owner>/<statefork-repo>.git'
export WAYPOINT_REPO_URL='https://github.com/<owner>/<waypoint-repo>.git'
```

Leave path overrides unset when the Linux user's `$HOME/statefork-agent` layout is acceptable.

## Bootstrap Command

After local config exists:

```bash
/path/to/skill/scripts/statefork_bootstrap.sh
```

One-shot remote bootstrap without writing local config first:

```bash
/path/to/skill/scripts/statefork_bootstrap.sh user@linux-vm
```

Local Linux:

```bash
/path/to/skill/scripts/statefork_bootstrap.sh --local
```

The bootstrap script:

1. Checks Linux requirements: `git`, `python3`, `python3 -m venv`, `go`, `sudo`, `criu`, and OverlayFS.
2. Reads existing Linux-side `~/.statefork-agent.env` before choosing paths, so configured paths are reused.
3. Clones StateFork and Waypoint if missing.
4. If repos already exist, pulls only when the checkout is clean; dirty checkouts are left untouched.
5. Builds Waypoint binaries: `waypoint` and `bash_init`.
6. Creates relative `waypoint` and `bash_init` symlinks in the StateFork root.
7. Reuses an existing StateFork venv when present, otherwise creates one.
8. Installs `requirements.txt` plus `paramiko`.
9. Writes Linux-side `~/.statefork-agent.env`.
10. Runs a basic import/version smoke test.

## Linux-Side Config

The generated Linux-side config looks like:

```bash
export STATEFORK_ROOT='/home/<linux-user>/statefork-agent/StateFork'
export WAYPOINT_ROOT='/home/<linux-user>/statefork-agent/Waypoint'
export STATEFORK_PYTHON='/home/<linux-user>/statefork-agent/StateFork/.venv/bin/python'
export STATEFORK_WORK_ROOT='/home/<linux-user>/statefork-agent/work'
export STATEFORK_REPO_URL='https://github.com/AndyGE44/Andy_StateFork.git'
export WAYPOINT_REPO_URL='https://github.com/AndyGE44/Andy_Waypoint.git'
```

Use repo URL overrides when a user wants a fork or private mirror.

## After Bootstrap

Run:

```bash
/path/to/skill/scripts/statefork_probe.sh
```

Then use project mode. Workspace roots should default to `$STATEFORK_WORK_ROOT`.

## Safety

The bootstrap script does not install OS packages by default. If commands such as `go`, `criu`, or `python3 -m venv` are missing, it prints an install hint and stops. Installing system packages should be explicit because it changes the user's VM.
