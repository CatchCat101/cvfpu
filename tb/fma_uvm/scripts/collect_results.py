#!/usr/bin/env python3
"""Summarize existing FMA UVM run logs without merging formats."""

from __future__ import annotations

import argparse
import json
import pathlib

from regress import (
    KNOWN_XFAIL_CFG,
    KNOWN_XFAIL_TEST,
    classify_known_early_valid_xfail,
    classify_log,
)


def run_identity(log: pathlib.Path) -> tuple[str, str, int | None]:
    cfg = log.parents[2].name
    test = log.parents[1].name
    seed_name = log.parent.name
    seed = int(seed_name.removeprefix("seed_")) if seed_name.startswith("seed_") else None
    return cfg, test, seed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_root", type=pathlib.Path)
    parser.add_argument("--suite", type=pathlib.Path)
    args = parser.parse_args()
    expectations: dict[tuple[str, str, int], str] = {}
    if args.suite is not None:
        suite = json.loads(args.suite.read_text())
        expectations = {
            (run["cfg"], run["test"], int(run["seed"])):
                run.get("expect", "pass")
            for run in suite["runs"]
        }

    failed = False
    for log in sorted(args.run_root.glob("**/run.log")):
        ok, detail = classify_log(log)
        cfg, test, seed = run_identity(log)
        expected = expectations.get((cfg, test, seed), "pass")
        if args.suite is None and cfg == KNOWN_XFAIL_CFG and test == KNOWN_XFAIL_TEST:
            expected = "xfail"

        if expected == "xfail":
            known, xfail_detail = classify_known_early_valid_xfail(log)
            if known:
                status, detail = "XFAIL", xfail_detail
            elif ok:
                status, detail = "XPASS", "known failure no longer occurs"
            else:
                status = "FAIL"
                detail = f"unexpected failure in XFAIL entry: {xfail_detail}"
        else:
            status = "PASS" if ok else "FAIL"

        failed |= status in {"FAIL", "XPASS"}
        print(f"{status} {log}: {detail}")
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
