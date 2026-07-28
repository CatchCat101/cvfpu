#!/usr/bin/env python3
"""Compile and run an FMA UVM suite independently for each FP format."""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import json
import pathlib
import re
import subprocess
import sys
from typing import Any


SUPPORTED_FORMATS = ("FP16", "FP32", "FP64")
KNOWN_XFAIL_CFG = "n2_inside"
KNOWN_XFAIL_TEST = "fma_flow_control_test"


def run_command(command: list[str], cwd: pathlib.Path) -> tuple[int, str]:
    completed = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    return completed.returncode, completed.stdout


def make_command(root: pathlib.Path, target: str, profile: str,
                 fp_format: str, run: dict[str, Any]) -> list[str]:
    return [
        "make", "-C", str(root / "tb/fma_uvm"), target,
        f"FORMAT={fp_format}", f"PROFILE={profile}",
        f"CFG={run['cfg']}", f"TEST={run['test']}",
        f"SEED={run['seed']}", f"NB_TXNS={run.get('num_txns', 0)}",
    ]


def log_path(root: pathlib.Path, fp_format: str,
             run: dict[str, Any]) -> pathlib.Path:
    return (
        root / "tb/fma_uvm/runs" / fp_format / run["cfg"] /
        run["test"] / f"seed_{run['seed']}" / "run.log"
    )


def classify_log(path: pathlib.Path) -> tuple[bool, str]:
    if not path.is_file():
        return False, "missing log"
    text = path.read_text(errors="replace")
    clean_uvm = (
        re.search(r"UVM_ERROR\s*:\s*0", text) is not None and
        re.search(r"UVM_FATAL\s*:\s*0", text) is not None
    )
    summary = re.search(
        r"SCB_SUMMARY.*?checked\s*=\s*(\d+).*?mismatches\s*=\s*(\d+)"
        r".*?unexpected_outputs\s*=\s*(\d+).*?pending\s*=\s*(\d+)",
        text,
        re.IGNORECASE,
    )
    scoreboard_ok = bool(summary and all(value == "0" for value in summary.groups()[1:]))
    assertion_failure = re.search(
        r"(?:Assertion|SVA).*?(?:fail|error)|Error:.*?(?:assert|checker)",
        text,
        re.IGNORECASE,
    ) is not None
    timeout = re.search(r"(?:drain|global).*timeout", text, re.IGNORECASE) is not None
    passed = clean_uvm and scoreboard_ok and not assertion_failure and not timeout
    if passed:
        return True, "pass"
    if timeout:
        return False, "timeout"
    if assertion_failure:
        return False, "assertion failure"
    if not clean_uvm:
        return False, "UVM error/fatal"
    return False, "scoreboard mismatch, missing summary, or pending records"


def classify_known_early_valid_xfail(path: pathlib.Path) -> tuple[bool, str]:
    """Accept only the documented n2_inside early-valid assertion failure.

    An expected failure is valid only when all numerical comparisons and UVM
    checks are clean and every VCS assertion failure is a_early_out_valid.
    """
    if not path.is_file():
        return False, "missing log"
    text = path.read_text(errors="replace")
    clean_uvm = (
        re.search(r"UVM_ERROR\s*:\s*0", text) is not None and
        re.search(r"UVM_FATAL\s*:\s*0", text) is not None
    )
    summary = re.search(
        r"SCB_SUMMARY.*?checked\s*=\s*(\d+).*?mismatches\s*=\s*(\d+)"
        r".*?unexpected_outputs\s*=\s*(\d+).*?pending\s*=\s*(\d+)",
        text,
        re.IGNORECASE,
    )
    scoreboard_ok = bool(summary and all(value == "0" for value in summary.groups()[1:]))
    failed_assertions = re.findall(
        r"^.*?started at \d+(?:ps|ns).*?failed at \d+(?:ps|ns).*$",
        text,
        re.IGNORECASE | re.MULTILINE,
    )
    only_known_assertion = bool(failed_assertions) and all(
        "a_early_out_valid" in line for line in failed_assertions
    )
    timeout = re.search(r"(?:drain|global).*timeout", text, re.IGNORECASE) is not None

    if clean_uvm and scoreboard_ok and only_known_assertion and not timeout:
        return True, "known a_early_out_valid assertion failure"
    if not clean_uvm:
        return False, "unexpected UVM error/fatal"
    if not scoreboard_ok:
        return False, "scoreboard mismatch, unexpected output, or pending record"
    if timeout:
        return False, "timeout"
    if not failed_assertions:
        return False, "known assertion did not fail"
    return False, "an assertion other than a_early_out_valid failed"


def parse_formats(value: str) -> list[str]:
    formats = [item.strip().upper() for item in value.split(",") if item.strip()]
    invalid = sorted(set(formats) - set(SUPPORTED_FORMATS))
    if invalid:
        raise argparse.ArgumentTypeError(
            f"unsupported format(s): {', '.join(invalid)}; choose FP16, FP32, FP64"
        )
    if not formats:
        raise argparse.ArgumentTypeError("at least one format is required")
    return formats


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=pathlib.Path, required=True)
    parser.add_argument("--suite", type=pathlib.Path, required=True)
    parser.add_argument("--formats", type=parse_formats, default=list(SUPPORTED_FORMATS))
    parser.add_argument("--profile", choices=("fast", "debug", "cov"), default="fast")
    parser.add_argument("--jobs", type=int, default=1)
    args = parser.parse_args()

    root = args.root.resolve()
    suite = json.loads(args.suite.read_text())
    if suite.get("name") == "signoff" and args.profile != "cov":
        print("signoff suite requires --profile cov", file=sys.stderr)
        return 2
    all_results: list[dict[str, Any]] = []
    coverage_failed = False

    selftest_rc, selftest_output = run_command(
        ["make", "-C", str(root / "tb/fma_uvm"), "selftest"], root
    )
    if selftest_rc:
        print(selftest_output, file=sys.stderr)
        return selftest_rc

    for fp_format in args.formats:
        runs = [run for run in suite["runs"]
                if fp_format in run.get("formats", SUPPORTED_FORMATS)]
        unique_cfgs = sorted({run["cfg"] for run in runs})
        compile_results: dict[str, tuple[int, str]] = {}

        def compile_cfg(cfg: str) -> tuple[str, int, str]:
            representative = next(run for run in runs if run["cfg"] == cfg)
            command = make_command(root, "compile", args.profile, fp_format,
                                   representative)
            rc, output = run_command(command, root)
            return cfg, rc, output

        with concurrent.futures.ThreadPoolExecutor(
                max_workers=max(1, args.jobs)) as pool:
            for cfg, rc, output in pool.map(compile_cfg, unique_cfgs):
                compile_results[cfg] = (rc, output)

        def execute(run: dict[str, Any]) -> dict[str, Any]:
            compile_rc, compile_output = compile_results[run["cfg"]]
            if compile_rc:
                return {
                    **run, "format": fp_format, "status": "COMPILE_FAIL",
                    "detail": compile_output[-4000:],
                }
            command = make_command(root, "run-only", args.profile, fp_format, run)
            rc, output = run_command(command, root)
            passed, detail = classify_log(log_path(root, fp_format, run))
            failed = rc != 0 or not passed
            if run.get("expect", "pass") == "xfail":
                known_xfail, xfail_detail = classify_known_early_valid_xfail(
                    log_path(root, fp_format, run)
                )
                if known_xfail:
                    status = "XFAIL"
                    detail = xfail_detail
                elif passed and rc == 0:
                    status = "XPASS"
                    detail = "known failure no longer occurs"
                else:
                    status = "FAIL"
                    detail = f"unexpected failure in XFAIL entry: {xfail_detail}"
            else:
                status = "FAIL" if failed else "PASS"
            return {
                **run, "format": fp_format, "status": status,
                "detail": detail, "returncode": rc, "tail": output[-1500:],
            }

        with concurrent.futures.ThreadPoolExecutor(
                max_workers=max(1, args.jobs)) as pool:
            format_results = list(pool.map(execute, runs))
        all_results.extend(format_results)

        stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
        report_dir = (
            root / "tb/fma_uvm/reports" / fp_format / suite["name"] / stamp
        )
        report_dir.mkdir(parents=True, exist_ok=True)

        coverage_result: dict[str, Any] = {"status": "NOT_RUN"}
        if suite.get("name") == "signoff":
            coverage_dir = report_dir / "coverage"
            coverage_command = [
                sys.executable,
                str(root / "tb/fma_uvm/scripts/coverage_report.py"),
                "--report", str(coverage_dir),
            ]
            for item in format_results:
                if item["status"] == "PASS":
                    run = item
                    vdb = log_path(root, fp_format, run).parent / "simv.vdb"
                    coverage_command.extend(("--vdb", str(vdb)))
            coverage_rc, coverage_output = run_command(coverage_command, root)
            if coverage_rc == 0:
                check_command = [
                    sys.executable,
                    str(root / "tb/fma_uvm/scripts/check_coverage.py"),
                    str(coverage_dir),
                    "--line", "95", "--branch", "95", "--condition", "95",
                    "--toggle", "90", "--functional", "100",
                ]
                check_rc, check_output = run_command(check_command, root)
                coverage_output += check_output
                coverage_rc = check_rc
            coverage_result = {
                "status": "PASS" if coverage_rc == 0 else "FAIL",
                "report": str(coverage_dir),
                "detail": coverage_output[-4000:],
            }
            coverage_failed |= coverage_rc != 0

        manifest = {
            "suite": suite["name"], "format": fp_format,
            "profile": args.profile, "generated_at": stamp,
            "softfloat_commit": "a0c6494cdc11865811dec815d5c0049fba9d82a8",
            "results": format_results, "coverage": coverage_result,
        }
        (report_dir / "summary.json").write_text(
            json.dumps(manifest, indent=2) + "\n"
        )
        lines = [
            f"{item['status']:12} {fp_format:4} {item['cfg']:12} "
            f"{item['test']:28} seed={item['seed']} {item['detail']}"
            for item in format_results
        ]
        if coverage_result["status"] != "NOT_RUN":
            lines.append(
                f"{coverage_result['status']:12} {fp_format:4} coverage "
                f"{coverage_result['report']}"
            )
        (report_dir / "summary.txt").write_text("\n".join(lines) + "\n")
        print("\n".join(lines))
        print(f"report: {report_dir}")

    bad = {"FAIL", "COMPILE_FAIL", "XPASS"}
    return 1 if (coverage_failed or
                 any(item["status"] in bad for item in all_results)) else 0


if __name__ == "__main__":
    sys.exit(main())
