#!/usr/bin/env python3
"""Interactive StateFork project driver.

Run this on the Linux VM from the StateFork repo root. It keeps one
EnvironmentManager alive while an agent edits a project and requests snapshots.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import traceback
from typing import Any


def load_statefork_env() -> None:
    config_path = os.environ.get("STATEFORK_CONFIG", os.path.expanduser("~/.statefork-agent.env"))
    if not os.path.exists(config_path):
        return
    with open(config_path, "r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[len("export "):]
            if "=" not in line:
                continue
            key, value = line.split("=", 1)
            value = value.strip().strip('"').strip("'")
            os.environ.setdefault(key.strip(), value)


def emit(event: str, **fields: Any) -> None:
    payload = {"event": event, **fields}
    print(json.dumps(payload, ensure_ascii=True), flush=True)


def build_decider(name: str, threshold: float):
    from decider import AlwaysFalseDecider, AlwaysTrueDecider, RandomDecider, ThresholdDecider

    if name == "always_true":
        return AlwaysTrueDecider()
    if name == "always_false":
        return AlwaysFalseDecider()
    if name == "random":
        return RandomDecider()
    if name == "threshold":
        return ThresholdDecider(threshold)
    raise ValueError(f"unknown decider: {name}")


def main() -> int:
    load_statefork_env()

    parser = argparse.ArgumentParser(description="Keep a StateFork project manager alive over stdin/stdout.")
    parser.add_argument("--workspace", required=True, help="Base workspace directory to manage.")
    parser.add_argument("--statefork-root", default=os.environ.get("STATEFORK_ROOT", "/users/alexxjk/Andy_StateFork"), help="StateFork repo root.")
    parser.add_argument("--build", action="store_true", help="Use Waypoint build mode for a Dockerfile/build context.")
    parser.add_argument("--decider", choices=["always_true", "always_false", "random", "threshold"], default="always_true")
    parser.add_argument("--threshold", type=float, default=5.0)
    args = parser.parse_args()

    statefork_root = os.path.abspath(args.statefork_root)
    sys.path.insert(0, statefork_root)
    os.chdir(statefork_root)

    from controller import create_env_manager

    workspace = os.path.abspath(args.workspace)
    os.makedirs(workspace, exist_ok=True)

    manager = create_env_manager(
        "ckpt_build",
        dockerfile_dir=workspace,
        build=args.build,
        decider=build_decider(args.decider, args.threshold),
    )

    labels: dict[str, str] = {}
    root_snapshot = getattr(manager, "last_snapshot_id", None)
    if root_snapshot:
        labels["initial"] = root_snapshot

    emit(
        "ready",
        session_id=getattr(manager, "session_id", None),
        statefork_root=statefork_root,
        workspace=workspace,
        work_dir=getattr(manager, "work_dir", None),
        root_snapshot=root_snapshot,
        decider=args.decider,
        commands=["workdir", "exec <command>", "snapshot [label]", "tree", "labels", "cleanup", "keep"],
    )

    try:
        for raw_line in sys.stdin:
            line = raw_line.strip()
            if not line:
                continue

            try:
                if line == "workdir":
                    emit("workdir", work_dir=getattr(manager, "work_dir", None))

                elif line == "tree":
                    emit("tree", tree=manager.print_snapshot_tree(), labels=labels)

                elif line == "labels":
                    emit("labels", labels=labels)

                elif line.startswith("snapshot"):
                    _, _, label = line.partition(" ")
                    label = label.strip()
                    snapshot_id = manager.snapshot()
                    if label and snapshot_id:
                        labels[label] = snapshot_id
                    emit(
                        "snapshot",
                        label=label or None,
                        snapshot_id=snapshot_id,
                        tree=manager.print_snapshot_tree(),
                        labels=labels,
                    )

                elif line.startswith("exec "):
                    command = line[5:].strip()
                    rc, stdout, stderr = manager.exec_command(command)
                    emit("exec", command=command, returncode=rc, stdout=stdout, stderr=stderr)

                elif line == "cleanup":
                    tree = manager.print_snapshot_tree()
                    manager.cleanup()
                    emit("cleanup", tree=tree, labels=labels)
                    return 0

                elif line == "keep":
                    emit(
                        "keep",
                        session_id=getattr(manager, "session_id", None),
                        work_dir=getattr(manager, "work_dir", None),
                        tree=manager.print_snapshot_tree(),
                        labels=labels,
                        warning="manager cleanup skipped; clean this session manually later",
                    )
                    manager.is_cleaned_up = True
                    return 0

                else:
                    emit("error", message=f"unknown command: {line}")

            except Exception as exc:  # Keep the driver alive after command-level failures.
                emit("error", message=str(exc), traceback=traceback.format_exc())

    finally:
        if not getattr(manager, "is_cleaned_up", False):
            manager.cleanup()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
