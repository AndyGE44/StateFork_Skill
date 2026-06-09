# StateFork Project Mode

Use this when the user wants the agent to build or modify a project inside a StateFork-managed environment, such as "build an app and snapshot as you go."

## Contract

Default behavior:

1. Run on the configured Linux host, for example `sf-exp`, or on local Linux with `--local`.
2. Put the user's project workspace outside the StateFork repos, preferably under `$STATEFORK_WORK_ROOT/<slug>`.
3. Start a StateFork `waypoint_build` manager against that workspace with `build=False` for normal app/project work.
4. Use `AlwaysTrueDecider` for coding projects so every snapshot is physical.
5. Do all project edits, dependency installs, tests, builds, generated files, and project artifacts inside the manager's `work_dir` on the VM.
6. Do not create or build the requested project on the local machine. Use local files only for the skill itself, helper scripts, and SSH orchestration.
7. Snapshot after each meaningful milestone.
8. Return the latest snapshot tree and final snapshot ID/label whenever the task is complete.

Default project mode is best for project filesystem state: source files, generated files, dependency files, and test results. It may print "Skipping memory checkpoint as per user request" when no shell/process PID is attached; that is acceptable for ordinary coding milestones. Current StateFork `waypoint_build(build=False)` calls Waypoint `init --quiet` and does not expose Waypoint's `init --shell` flag. If the user asks to preserve live process memory in a non-Dockerfile workspace, use Waypoint CLI `init --shell` or a target PID first, then attach with StateFork `waypoint_attach`, or extend the StateFork manager/driver deliberately.

## Dockerfile Decision Rule

Do not infer Dockerfile mode from the word "build" alone.

Use `build=False` for:

- "build an app"
- "create a website"
- "make a FastAPI/React/CLI project"
- "implement a feature"
- "debug this project"
- projects where Python/Node/etc. dependencies can be installed inside the managed work directory

Use `build=True` only when the user explicitly asks for or the task clearly requires:

- a Dockerfile
- a container image/build context
- a containerized environment
- installing OS/system packages such as with `apt`
- daemon/service-level dependencies that should be baked into a Linux environment
- reproducing an environment from Dockerfile instructions

When using `build=True`, create or update the Dockerfile/build context first, then pass `--build` to the driver or `build=True` to `create_env_manager`.

## Memory Checkpoint Modes

StateFork's current Waypoint wrapper has these practical modes:

| Mode | How it starts | Dockerfile required | Shell PID available automatically | Memory checkpoint by default |
|---|---|---:|---:|---:|
| `waypoint_build(build=False)` | Waypoint `init <workspace> --quiet` | No | No | No, filesystem only unless a PID is supplied later |
| `waypoint_build(build=True)` | Waypoint `build <context> --quiet` | Yes | Yes | Yes, it uses the built sandbox shell when PID is omitted |
| `waypoint_attach(session_id, target_pid=-2)` | Attach to existing Waypoint session | Depends on existing session | Yes only if the session was created with shell | Yes if shell/target PID exists, otherwise filesystem only |

Waypoint CLI supports `init <workspace> --quiet --shell`, but the current StateFork `WaypointBuildManager(build=False)` does not pass `--shell`. To use that ability from StateFork today, create the session with Waypoint CLI first, then use `waypoint_attach` with the returned session ID. Legacy aliases `ckpt_build` and `ckpt_attach` may still work, but prefer the Waypoint names.

## Driver-Based Workflow

Use the bundled driver when the work spans multiple commands or tool calls. Copy it to the VM:

```bash
scp /path/to/skill/scripts/statefork_project_driver.py sf-exp:/tmp/statefork_project_driver.py
```

Prepare a base workspace:

```bash
ssh sf-exp '. ~/.statefork-agent.env && mkdir -p "$STATEFORK_WORK_ROOT/my-app-base"'
```

Start the persistent driver from the StateFork repo root:

```bash
ssh -t sf-exp '. ~/.statefork-agent.env && cd "$STATEFORK_ROOT" && sudo "$STATEFORK_PYTHON" /tmp/statefork_project_driver.py --workspace "$STATEFORK_WORK_ROOT/my-app-base"'
```

For explicit Dockerfile/container mode:

```bash
ssh -t sf-exp '. ~/.statefork-agent.env && cd "$STATEFORK_ROOT" && sudo "$STATEFORK_PYTHON" /tmp/statefork_project_driver.py --workspace "$STATEFORK_WORK_ROOT/my-app-base" --build'
```

The driver reads `~/.statefork-agent.env`, so it can be run from another current directory as long as the StateFork venv interpreter is used.

The driver prints JSON lines. The `ready` event includes:

```json
{"event": "ready", "session_id": "...", "work_dir": "...", "root_snapshot": "..."}
```

Keep that terminal session open while working. Send commands as plain lines:

```text
workdir
exec pwd
exec python --version
snapshot after-setup
tree
labels
cleanup
```

Use separate SSH commands to inspect or edit `work_dir` when convenient. If permissions require root, use `sudo`. For commands that should be replayable by virtual snapshots, run them through `exec`; for default project mode this is less important because snapshots are physical.

## Snapshot Milestones

Take snapshots with short labels:

```text
snapshot baseline
snapshot scaffold-created
snapshot dependencies-installed
snapshot feature-routing
snapshot tests-passing
snapshot final
```

The driver tracks labels separately from StateFork's native snapshot IDs, because StateFork's tree prints IDs.

## Final Response Shape

For project tasks, include:

```text
StateFork session: <session_id>
Work dir: <work_dir>
Final snapshot: <label> = <snapshot_id>
Snapshot tree:
<tree>
```

If the task was ephemeral and the driver was cleaned up, say so:

```text
Live StateFork session was cleaned up after printing the tree.
```

If the user asked to preserve the session, use the driver `keep` command, report the session ID, and warn that manual cleanup will be needed later.

## Direct Python Pattern

For short tasks that fit in one Python script:

```python
from controller import create_env_manager
from decider import AlwaysTrueDecider

manager = create_env_manager(
    "waypoint_build",
    dockerfile_dir="/path/from/STATEFORK_WORK_ROOT/my-app-base",
    build=False,
    decider=AlwaysTrueDecider(),
)

try:
    print("work_dir", manager.work_dir)
    baseline = manager.snapshot()
    # Write files under manager.work_dir or run commands with manager.exec_command(...)
    after_scaffold = manager.snapshot()
    print("final", after_scaffold)
    print(manager.print_snapshot_tree())
finally:
    manager.cleanup()
```

For longer tasks, prefer the persistent driver so the manager's in-memory snapshot tree survives between milestones.
