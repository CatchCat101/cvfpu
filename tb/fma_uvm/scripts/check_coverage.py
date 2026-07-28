#!/usr/bin/env python3
"""Check the percentages emitted by a VCS URG text report."""

from __future__ import annotations

import argparse
import pathlib
import re


LABELS = {
    "line": ("line",),
    "branch": ("branch",),
    "condition": ("condition", "cond"),
    "toggle": ("toggle", "tgl"),
    "functional": ("group", "functional"),
}


def find_percentage(text: str, aliases: tuple[str, ...]) -> float | None:
    for alias in aliases:
        patterns = (
            rf"\b{alias}\b[^\n%]*?([0-9]+(?:\.[0-9]+)?)\s*%",
            rf"([0-9]+(?:\.[0-9]+)?)\s*%[^\n]*?\b{alias}\b",
        )
        for pattern in patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                return float(match.group(1))
    return None


def parse_urg_text_report(report: pathlib.Path) -> dict[str, float]:
    """Read DUT code metrics and the lowest mandatory covergroup score."""
    if not report.is_dir():
        return {}

    values: dict[str, float] = {}
    hierarchy_path = report / "hierarchy.txt"
    if hierarchy_path.is_file():
        for line in hierarchy_path.read_text(errors="replace").splitlines():
            fields = line.split()
            if fields and fields[-1] == "dut" and len(fields) >= 7:
                # SCORE LINE COND TOGGLE BRANCH ASSERT NAME
                names = ("line", "condition", "toggle", "branch")
                for name, field in zip(names, fields[1:5]):
                    if field != "--":
                        values[name] = float(field)
                break

    groups_path = report / "groups.txt"
    if groups_path.is_file():
        mandatory = {
            "fma_env_pkg::fma_coverage::input_cg",
            "fma_env_pkg::fma_coverage::checked_result_cg",
            "fma_env_pkg::fma_coverage::control_cg",
        }
        scores: list[float] = []
        for line in groups_path.read_text(errors="replace").splitlines():
            if any(name in line for name in mandatory):
                fields = line.split()
                if fields:
                    scores.append(float(fields[0]))
        if len(scores) == len(mandatory):
            values["functional"] = min(scores)
    return values


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=pathlib.Path)
    for name in LABELS:
        parser.add_argument(f"--{name}", type=float, required=True)
    args = parser.parse_args()

    parsed = parse_urg_text_report(args.report)
    candidates = [args.report] if args.report.is_file() else list(
        args.report.glob("**/*.txt"))
    text = "\n".join(path.read_text(errors="replace") for path in candidates)
    failed = False
    for name, aliases in LABELS.items():
        actual = parsed.get(name, find_percentage(text, aliases))
        required = getattr(args, name)
        if actual is None:
            print(f"{name}: percentage not found")
            failed = True
        else:
            print(f"{name}: {actual:.2f}% (required {required:.2f}%)")
            failed |= actual < required
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
