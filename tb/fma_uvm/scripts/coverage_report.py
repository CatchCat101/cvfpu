#!/usr/bin/env python3
"""Merge FMA VCS coverage databases without expected-failure runs."""

from __future__ import annotations

import argparse
import pathlib
import subprocess

from regress import classify_log


KNOWN_XFAIL_CFG = "n2_inside"
KNOWN_XFAIL_TEST = "fma_flow_control_test"


def discover_vdbs(run_root: pathlib.Path, fp_format: str) -> list[pathlib.Path]:
    format_root = run_root / fp_format
    databases: list[pathlib.Path] = []
    for path in sorted(format_root.glob("*/*/seed_*/simv.vdb")):
        relative = path.relative_to(format_root).parts
        cfg, test = relative[0], relative[1]
        if cfg == KNOWN_XFAIL_CFG and test == KNOWN_XFAIL_TEST:
            continue
        passed, _ = classify_log(path.parent / "run.log")
        if not passed:
            continue
        databases.append(path)
    return databases


def add_compile_databases(databases: list[pathlib.Path]) -> list[pathlib.Path]:
    """Add the compile-time design VDB required by each runtime VDB."""
    complete = {path.resolve() for path in databases}
    for path in list(complete):
        parts = path.parts
        if "runs" not in parts:
            continue
        runs_index = len(parts) - 1 - parts[::-1].index("runs")
        if len(parts) <= runs_index + 2:
            continue
        fp_format = parts[runs_index + 1]
        cfg = parts[runs_index + 2]
        fma_uvm_root = pathlib.Path(*parts[:runs_index])
        complete.add(
            (fma_uvm_root / "build" / fp_format / cfg / "cov" / "simv.vdb").resolve()
        )
    return sorted(complete)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=pathlib.Path, required=True)
    parser.add_argument("--vdb", type=pathlib.Path, action="append", default=[])
    parser.add_argument("--run-root", type=pathlib.Path)
    parser.add_argument("--format", choices=("FP16", "FP32", "FP64"))
    args = parser.parse_args()

    databases = list(args.vdb)
    if not databases:
        if args.run_root is None or args.format is None:
            parser.error("provide --vdb or both --run-root and --format")
        databases = discover_vdbs(args.run_root, args.format)

    databases = add_compile_databases(databases)
    missing = [path for path in databases if not path.is_dir()]
    if missing:
        for path in missing:
            print(f"missing coverage database: {path}")
        return 2
    if not databases:
        print("no non-XFAIL coverage databases found")
        return 2

    args.report.mkdir(parents=True, exist_ok=True)
    command = [
        "urg", "-full64", "-metric", "line+cond+branch+tgl+assert+group",
        "-format", "both", "-dir",
    ]
    command.extend(str(path) for path in databases)
    command.extend(("-report", str(args.report)))
    completed = subprocess.run(command, check=False)
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
