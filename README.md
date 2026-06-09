# StateFork Skill

Codex skill for using StateFork and Waypoint as a Linux checkpoint/restore project sandbox.

## Install

Install into Codex with the skill installer:

```bash
python3 ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo AndyGE44/StateFork_Skill \
  --path statefork
```

Restart Codex after installation.

## Use

Invoke the skill in a prompt:

```text
Use $statefork to build a small app inside a StateFork environment. Snapshot milestones and return the snapshot tree.
```

The skill expects a Linux environment because StateFork and Waypoint rely on CRIU, OverlayFS, and sudo/root-capable checkpoint operations.

## Bootstrap A Linux VM

The user only needs to provide an SSH target or run on local Linux:

```bash
statefork/scripts/statefork_bootstrap.sh <ssh-host>
statefork/scripts/statefork_bootstrap.sh --local
```

The bootstrap script checks dependencies, clones or updates StateFork and Waypoint, builds Waypoint, creates the StateFork Python venv, writes `~/.statefork-agent.env`, and verifies imports.

After bootstrap:

```bash
statefork/scripts/statefork_probe.sh <ssh-host>
```

## Project Policy

- Normal app/project development uses `waypoint_build(build=False)`.
- Dockerfile/container mode uses `build=True` only when explicitly needed for system packages, container environments, or memory-capable shell workflows.
- All project files, installs, tests, and build artifacts should be created inside the StateFork-managed `work_dir` on the Linux host.
- The agent should snapshot meaningful milestones and report the final snapshot tree.
