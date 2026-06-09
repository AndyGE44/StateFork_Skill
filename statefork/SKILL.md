---
name: statefork
description: Use StateFork/State Fork and Waypoint for Linux-only checkpoint/restore, snapshot trees, project sandboxes, agent coding environments, virtual-vs-physical snapshot experiments, backend debugging, and benchmark workflows. Trigger when Codex needs to use StateFork as a sandbox while building an app or project, automatically snapshot project milestones and report the snapshot tree, run or modify StateFork, use the Waypoint backend, connect to a configured or user-provided Linux host, checkpoint/restore a process or shell session, inspect StateFork controller managers or deciders, or troubleshoot CRIU/OverlayFS/container snapshotting.
---

# StateFork

## Core Rule

Run real checkpoint/restore work on Linux. StateFork and Waypoint rely on Linux features such as CRIU, OverlayFS, namespaces, and usually sudo/root-capable operations.

Do not assume a default VM. Use one of:

- an explicit SSH target from the user, such as `user@linux-vm`
- a configured local file at `~/.statefork-skill.env` containing `STATEFORK_HOST`
- local Linux only when the user confirms it or `STATEFORK_LOCAL=1` is configured

The skill installer only copies files; it does not run this skill's scripts or prompt for configuration. On first use, if `~/.statefork-skill.env` is missing and no SSH target was supplied, ask the user for either an SSH target or confirmation to use local Linux. If the user wants to configure later, explain that they can create `~/.statefork-skill.env` manually or run `scripts/statefork_configure.sh` later.

For setup details, read `references/setup.md`. The short path is:

```bash
/path/to/skill/scripts/statefork_configure.sh --host user@linux-vm
/path/to/skill/scripts/statefork_bootstrap.sh
```

Or, on a Linux machine:

```bash
/path/to/skill/scripts/statefork_configure.sh --local
/path/to/skill/scripts/statefork_bootstrap.sh
```

Use `scripts/statefork_probe.sh` before nontrivial work to confirm SSH/local target selection, repo paths, binaries, imports, sudo visibility, CRIU, and OverlayFS. The probe reads local `~/.statefork-skill.env` and Linux-side `~/.statefork-agent.env` when present.

When using this skill to build or modify a project, create, edit, install, test, and build everything inside the StateFork-managed environment on the Linux host. Do not scaffold project files, install dependencies, run app builds, or produce project artifacts on the local machine; local work should be limited to skill files, orchestration, and SSH commands.

## Default Project Sandbox Workflow

When the user asks to build, modify, debug, or test a project with StateFork, treat StateFork as the working environment, not merely as the subject being inspected.

1. Probe the environment:

```bash
/path/to/skill/scripts/statefork_probe.sh
```

If setup is missing, read `references/setup.md` and run `scripts/statefork_configure.sh` plus `scripts/statefork_bootstrap.sh`.

2. Read `references/project-mode.md` for the project sandbox protocol. Use `scripts/statefork_project_driver.py` when a task needs multiple edits, commands, and snapshots while preserving one live StateFork manager.

3. Create or select a project workspace on the Linux host, usually under `$STATEFORK_WORK_ROOT` and outside the StateFork/Waypoint repos:

```text
$STATEFORK_WORK_ROOT/<project-name>
```

4. Choose the StateFork build mode:

- For ordinary requests like "build an app", "make a project", "create a website", or "implement this feature", use `waypoint_build` with `build=False`. Do not create a Dockerfile just because the user said "build".
- Use `build=True` only when the user explicitly asks for a Dockerfile, container environment, image/build context, OS/system packages, `apt`, service-level dependencies, or otherwise needs a reproducible container-like Linux environment.

5. Start a StateFork-managed environment for that workspace and do the project work inside the manager's `work_dir`. For coding projects, default to all-physical snapshots with `AlwaysTrueDecider`; virtual snapshots only replay commands issued through `manager.exec_command()` and can miss direct file edits.

Current StateFork `waypoint_build(build=False)` calls Waypoint `init --quiet` and does not expose `init --shell`. If the user needs a live process or shell memory state preserved without Dockerfile mode, first create a Waypoint session with `init --shell` or a target PID, then attach with StateFork `waypoint_attach`.

6. Take snapshots at meaningful milestones:

- after environment setup
- after scaffold or dependency install
- after each coherent feature/change
- after tests or verification pass
- before risky experiments
- after final completion

7. Every final response for a StateFork project task must include the latest snapshot tree and the final snapshot ID or label. If cleanup is performed, print the tree before cleanup and say that the live session was cleaned up.

## StateFork Internals Workflow

Read `references/repo-map.md` when you need command examples, source landmarks, backend semantics, build steps, or troubleshooting details.

Use Linux-side config values from `~/.statefork-agent.env`:

```bash
. ~/.statefork-agent.env
cd "$STATEFORK_ROOT"
```

The Waypoint backend is registered as:

```python
from controller import create_env_manager

manager = create_env_manager("waypoint_build", dockerfile_dir="/path/to/workload", build=False)
```

Use `build=False` for an ordinary existing workspace or app project. Use `build=True` only when the target directory is intentionally a Dockerfile/build context and the Linux host has the build dependencies available.

For direct backend operations, use the Waypoint CLI in `$WAYPOINT_ROOT`, or the StateFork root symlinks `$STATEFORK_ROOT/waypoint` and `$STATEFORK_ROOT/bash_init`.

Clean up sessions after experiments unless the user explicitly wants the live StateFork session preserved. If normal cleanup fails, use the backend's force cleanup path.

## Snapshot Guidance

- Physical snapshots call the backend checkpoint path and are restorable directly.
- Virtual snapshots only record commands issued through `EnvironmentManager.exec_command()`. Commands run outside the manager are not replayable.
- Restore of a virtual snapshot restores the nearest physical ancestor first, then replays logged commands in order.
- Use `always_true` for all-physical behavior, `always_false` for virtual behavior, `random` for mixed behavior, and `threshold` for physical snapshots after cumulative exec time crosses a threshold.
- For project-building tasks, use physical snapshots by default because direct file edits in `work_dir` are captured by physical snapshots but are not captured as replay commands for virtual snapshots.

## Common Cautions

- CRIU, OverlayFS, and the Waypoint backend require Linux and usually root/sudo.
- Network connections may not survive checkpoint/restore.
- The StateFork Waypoint manager expects `waypoint` and `bash_init` symlinks in the StateFork repo root.
- Legacy `ckpt_build` and `ckpt_attach` aliases may still exist for compatibility; prefer `waypoint_build` and `waypoint_attach`.
