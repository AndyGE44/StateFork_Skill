# StateFork Repo Map

Use this when you need source landmarks, backend semantics, direct command examples, build steps, or troubleshooting details.

## Configured Layout

Do not assume fixed hostnames or absolute paths. Source the Linux-side config:

```bash
. ~/.statefork-agent.env
printf '%s\n' "$STATEFORK_ROOT" "$WAYPOINT_ROOT" "$STATEFORK_WORK_ROOT"
```

Default bootstrap paths, when the user did not override them:

```text
$HOME/statefork-agent/StateFork
$HOME/statefork-agent/Waypoint
$HOME/statefork-agent/work
```

The VM may not have `rg`; use `find` and `grep` if needed.

## What Each Repo Does

`StateFork` is the Python controller, shell, decider, and benchmarking layer. It manages snapshot trees and abstracts multiple backends including Docker, Podman, CRIU, Hybrid Podman+CRIU, gVisor, Firecracker, and Waypoint.

`Waypoint` is the Go/Linux backend that combines OverlayFS filesystem state with CRIU memory/process state. It also manages PTY-backed shell sessions so commands can preserve shell state across checkpoints.

## Key StateFork Files

```text
README.md                              project overview, backend table, requirements
controller/__init__.py                 create_env_manager factory and method names
controller/base_env_manager.py         snapshot tree, virtual snapshot replay, exec logging
controller/waypoint_env_manager.py     StateFork integration with Waypoint
controller/*_env_manager.py            backend-specific managers
decider/decider.py                     AlwaysTrue, AlwaysFalse, Random, Threshold deciders
interface/shell.py                     interactive CLI and --method/--decider mappings
scripts/benchmark_all.py               benchmark/timeline example
Dockerfile                             sample FastAPI build context
```

Factory methods of interest:

```text
waypoint_build      WaypointBuildManager(dockerfile_dir=None, build=True, decider=None)
waypoint_attach     WaypointAttachManager(session_id, target_pid=-2, decider=None)
ckpt_build          legacy alias for waypoint_build
ckpt_attach         legacy alias for waypoint_attach
```

Interactive shell mapping:

```bash
. ~/.statefork-agent.env
cd "$STATEFORK_ROOT"
sudo "$STATEFORK_PYTHON" -m interface.shell --method waypoint --decider always_true
sudo "$STATEFORK_PYTHON" -m interface.shell --method waypoint --decider threshold --threshold 5
```

The shell does not expose `dockerfile_dir` or `build=False`; it creates a `waypoint_build` manager with default arguments. For arbitrary workspaces, prefer a small Python snippet or the bundled project driver.

## Key Waypoint Files

```text
README.md                     usage, architecture, limitations
cmd/waypoint/main.go          CLI commands and version
cmd/bash-init/main.go         shell-session helper binary
pkg/waypoint/types.go         session metadata and config env vars
pkg/waypoint/session.go       session lifecycle
pkg/waypoint/manager.go       manager construction/loading
pkg/waypoint/filesystem.go    OverlayFS handling
pkg/waypoint/memory.go        CRIU handling
pkg/waypoint/exec.go          command execution
pkg/waypoint/build.go         buildah/Dockerfile workflow
```

CLI commands:

```bash
sudo ./waypoint init <work-directory> [--quiet] [--shell]
sudo ./waypoint build <dockerfile-directory> [--quiet]
sudo ./waypoint create <session> <checkpoint-id> [pid | -1]
sudo ./waypoint restore <session> <checkpoint-id>
sudo ./waypoint exec <session> <command> [args...]
sudo ./waypoint list <session>
sudo ./waypoint cleanup <session> [--force]
./waypoint version
```

Special PID values:

```text
-1  skip memory checkpoint
-2  PID not provided; checkpoint shell if enabled, otherwise skip memory
0   shell not enabled
```

## Binary Expectations

StateFork's Waypoint manager uses binaries from the StateFork repo root:

```text
$STATEFORK_ROOT/waypoint
$STATEFORK_ROOT/bash_init
```

The bootstrap script builds binaries in `$WAYPOINT_ROOT` and creates relative symlinks in `$STATEFORK_ROOT`. Manual rebuild:

```bash
. ~/.statefork-agent.env
cd "$WAYPOINT_ROOT"
go build -o waypoint cmd/waypoint/main.go
go build -o bash_init cmd/bash-init/main.go
ln -sfn "$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$WAYPOINT_ROOT/waypoint" "$STATEFORK_ROOT")" "$STATEFORK_ROOT/waypoint"
ln -sfn "$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$WAYPOINT_ROOT/bash_init" "$STATEFORK_ROOT")" "$STATEFORK_ROOT/bash_init"
```

## Python Environment

StateFork needs the packages in `requirements.txt`. It also needs `paramiko` when importing `controller`, because `controller/__init__.py` eagerly imports Firecracker support and `firecracker_env_manager.py` imports `paramiko`.

Recommended setup when imports fail:

```bash
. ~/.statefork-agent.env
cd "$STATEFORK_ROOT"
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt paramiko
```

Then run StateFork with:

```bash
. ~/.statefork-agent.env
cd "$STATEFORK_ROOT"
sudo "$STATEFORK_PYTHON" -m interface.shell --method waypoint --decider always_true
```

Or run the probe:

```bash
/path/to/skill/scripts/statefork_probe.sh
```

## Programmatic StateFork Examples

Existing workspace, no Dockerfile build:

```bash
ssh user@linux-vm '. ~/.statefork-agent.env && cd "$STATEFORK_ROOT" && sudo "$STATEFORK_PYTHON" - <<'"'"'PY'"'"'
import os
from controller import create_env_manager
from decider import AlwaysTrueDecider

workspace = os.path.join(os.environ["STATEFORK_WORK_ROOT"], "example-app")
os.makedirs(workspace, exist_ok=True)

manager = create_env_manager(
    "waypoint_build",
    dockerfile_dir=workspace,
    build=False,
    decider=AlwaysTrueDecider(),
)
try:
    print("work_dir", manager.work_dir)
    rc, out, err = manager.exec_command("pwd")
    print("exec", rc, out, err)
    sid = manager.snapshot()
    print("snapshot", sid)
    print(manager.print_snapshot_tree())
finally:
    manager.cleanup()
PY'
```

This StateFork path calls Waypoint `init <workspace> --quiet`, not `init --shell`; snapshots will be filesystem-only unless a target PID or shell-enabled existing session is attached.

Existing workspace with shell memory checkpointing requires creating the shell-enabled Waypoint session first:

```bash
ssh user@linux-vm '. ~/.statefork-agent.env && cd "$STATEFORK_ROOT" && sudo ./waypoint init "$STATEFORK_WORK_ROOT/example-app" --quiet --shell'
```

Then attach by session ID:

```python
from controller import create_env_manager

manager = create_env_manager("waypoint_attach", session_id="SESSION_ID", target_pid=-2)
```

With `target_pid=-2`, Waypoint checkpoints the shell PID if the loaded session has one; otherwise it skips memory checkpointing.

Dockerfile/build context:

```python
from controller import create_env_manager

manager = create_env_manager("waypoint_build", dockerfile_dir="/path/to/build-context", build=True)
try:
    manager.exec_command("python --version")
    sid = manager.snapshot()
    manager.restore(sid)
finally:
    manager.cleanup()
```

Attach to an existing Waypoint session:

```python
from controller import create_env_manager

manager = create_env_manager("waypoint_attach", session_id="SESSION_ID", target_pid=-2)
try:
    sid = manager.snapshot()
    manager.restore(sid)
finally:
    manager.cleanup()
```

## Direct Waypoint Examples

Build or verify binaries:

```bash
ssh user@linux-vm '. ~/.statefork-agent.env && cd "$WAYPOINT_ROOT" && go build -o waypoint cmd/waypoint/main.go && go build -o bash_init cmd/bash-init/main.go && ./waypoint version'
```

Initialize a workspace and run commands through a shell session:

```bash
ssh user@linux-vm '. ~/.statefork-agent.env && cd "$WAYPOINT_ROOT" && sudo ./waypoint init "$STATEFORK_WORK_ROOT/example-app" --quiet --shell'
```

The quiet `init` output is:

```text
SESSION_ID,WORK_DIR
```

Create, inspect, restore, and clean up:

```bash
sudo ./waypoint exec <session> 'echo hello > note.txt'
sudo ./waypoint create <session> before-change
sudo ./waypoint exec <session> 'echo changed >> note.txt'
sudo ./waypoint restore <session> before-change
sudo ./waypoint exec <session> 'cat note.txt'
sudo ./waypoint list <session>
sudo ./waypoint cleanup <session>
```

If cleanup fails:

```bash
sudo ./waypoint cleanup <session> --force
```

## Snapshot And Decider Semantics

`EnvironmentManager.snapshot()` asks its `decider` whether to take a physical snapshot.

Physical snapshot:

- Calls backend `_core_snapshot()`.
- Records a concrete backend snapshot ID.
- Resets cumulative exec time.

Virtual snapshot:

- Creates an ID like `v1234567`.
- Stores commands logged since the parent snapshot.
- Does not call backend checkpoint.
- Retains cumulative exec time for threshold policies.

`EnvironmentManager.restore(snapshot_id)` restores physical snapshots directly. For a virtual snapshot, it walks up to the nearest physical ancestor, restores that, then replays commands stored on each virtual node.

Only commands issued through `manager.exec_command(...)` are logged for virtual replay.

Deciders:

```python
from decider import AlwaysTrueDecider, AlwaysFalseDecider, RandomDecider, ThresholdDecider
```

- `AlwaysTrueDecider`: always physical.
- `AlwaysFalseDecider`: always virtual.
- `RandomDecider`: random physical/virtual.
- `ThresholdDecider(threshold)`: physical when cumulative exec time reaches the threshold in seconds.

## Troubleshooting

Use the probe first:

```bash
/path/to/skill/scripts/statefork_probe.sh
```

Common problems:

- No Linux target configured: run `scripts/statefork_configure.sh --host user@linux-vm` or `scripts/statefork_configure.sh --local`.
- `waypoint: not found`: build Waypoint and symlink `waypoint` to the StateFork root, or rerun bootstrap.
- `bash_init` missing: build `cmd/bash-init/main.go` and symlink it to the StateFork root.
- `ModuleNotFoundError: No module named 'psutil'`: install `requirements.txt` in a Linux venv.
- `ModuleNotFoundError: No module named 'paramiko'`: install `paramiko`; this is required for eager controller imports even if Firecracker is not being used.
- CRIU failure: check `criu --version`, `sudo criu check`, and kernel support.
- OverlayFS failure: verify `overlay` appears in `/proc/filesystems`.
- Build mode failure: `waypoint_build` with `build=True` requires a Dockerfile/build context and buildah support.
- Sudo hangs over SSH: run with an interactive TTY, for example `ssh -t user@linux-vm ...`, or ask the user to authenticate on the VM.
- Virtual restore replays the wrong state: ensure all mutating commands went through `manager.exec_command`, not a side shell.
- Network state vanished after restore: this is a known Waypoint limitation.
- Leftover mounts/session directories: inspect `/tmp/waypoint-sessions` and `/tmp/waypoint-sessions-info`, then use force cleanup when safe.
