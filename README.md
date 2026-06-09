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

The installer only downloads the skill files. It does not run setup scripts and cannot prompt for a VM during installation.

## Configure

After install, configure either an SSH-accessible Linux VM:

```bash
~/.codex/skills/statefork/scripts/statefork_configure.sh --host user@linux-vm
~/.codex/skills/statefork/scripts/statefork_bootstrap.sh
```

Or configure local Linux:

```bash
~/.codex/skills/statefork/scripts/statefork_configure.sh --local
~/.codex/skills/statefork/scripts/statefork_bootstrap.sh
```

You can also skip configuration and let the agent ask for an SSH target the first time you use `$statefork`.

The local config lives at `~/.statefork-skill.env`. The Linux-side runtime config lives at `~/.statefork-agent.env`.

## Use

Invoke the skill in a prompt:

```text
Use $statefork to build a small app inside a StateFork environment. Snapshot milestones and return the snapshot tree.
```

The skill expects Linux because StateFork and Waypoint rely on CRIU, OverlayFS, and sudo/root-capable checkpoint operations.

## Project Policy

- Normal app/project development uses `waypoint_build(build=False)`.
- Dockerfile/container mode uses `build=True` only when explicitly needed for system packages, container environments, or memory-capable shell workflows.
- All project files, installs, tests, and build artifacts should be created inside the StateFork-managed `work_dir` on the Linux host.
- The agent should snapshot meaningful milestones and report the final snapshot tree.
