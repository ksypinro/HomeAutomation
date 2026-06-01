#!/usr/bin/env python3
"""Run the full golden evaluation workflow safely in sequence.

Stages:
1. Generate expected dataset contracts through Codex CLI by default.
2. Run the HomeAutomation project against that dataset to create actual output.
3. Compare expected vs actual and write accuracy reports.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = Path(__file__).resolve().parent
PACKAGE_DIR = REPO_ROOT / "HomeAutomationCore"
DEFAULT_DATASET = PACKAGE_DIR / ".build" / "generated-evals" / "full-v1"
DEFAULT_OUTPUT = PACKAGE_DIR / ".build" / "evaluation-full-v1"


def parse_bool(value: str | bool) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "y", "on"}:
        return "true"
    if normalized in {"0", "false", "no", "n", "off"}:
        return "false"
    raise argparse.ArgumentTypeError(f"Expected a boolean value, got {value!r}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate, run, and compare a golden evaluation dataset.")
    parser.add_argument("--package-dir", type=Path, default=PACKAGE_DIR)
    parser.add_argument("--dataset-output", type=Path, default=DEFAULT_DATASET)
    parser.add_argument("--actual-output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--dataset-name", default="full-v1")
    parser.add_argument("--fixture-limit", type=int, default=100)
    parser.add_argument("--case-limit", type=int, default=10_000)
    parser.add_argument(
        "--generation-mode",
        choices=["codex", "template", "foundation-model"],
        default="codex",
    )
    parser.add_argument("--mode", choices=["deterministic", "live"], default="deterministic")
    parser.add_argument("--suite", default="all")
    parser.add_argument("--compare-traces", type=parse_bool, default="true")
    parser.add_argument("--write-actual-traces", type=parse_bool, default="true")
    parser.add_argument("--require-live-model", type=parse_bool, default="false")
    parser.add_argument("--allow-evaluation-failures", type=parse_bool, default="true")
    parser.add_argument("--fail-under-pass-rate", type=float)
    parser.add_argument("--codex-path")
    parser.add_argument("--codex-model")
    parser.add_argument("--codex-profile")
    parser.add_argument("--skip-codex-preflight", action="store_true")
    parser.add_argument("--skip-generate", action="store_true")
    parser.add_argument("--skip-run", action="store_true")
    parser.add_argument("--skip-compare", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def run_stage(name: str, command: list[str], dry_run: bool) -> dict[str, Any]:
    started_at = now_iso()
    print(f"\n== {name} ==")
    print("+", " ".join(command))
    if dry_run:
        return {
            "name": name,
            "command": command,
            "startedAt": started_at,
            "completedAt": now_iso(),
            "exitCode": 0,
            "dryRun": True,
        }
    completed = subprocess.run(command, text=True, check=False)
    return {
        "name": name,
        "command": command,
        "startedAt": started_at,
        "completedAt": now_iso(),
        "exitCode": completed.returncode,
        "dryRun": False,
    }


def append_optional(command: list[str], flag: str, value: str | None) -> None:
    if value:
        command.extend([flag, value])


def main() -> int:
    args = parse_args()
    package_dir = args.package_dir.resolve()
    dataset_output = args.dataset_output.resolve()
    actual_output = args.actual_output.resolve()
    stages: list[dict[str, Any]] = []

    if not args.skip_generate:
        command = [
            sys.executable,
            str(SCRIPT_DIR / "create_dataset_with_codex.py"),
            "--package-dir",
            str(package_dir),
            "--output",
            str(dataset_output),
            "--dataset-name",
            args.dataset_name,
            "--fixture-limit",
            str(args.fixture_limit),
            "--case-limit",
            str(args.case_limit),
            "--generation-mode",
            args.generation_mode,
        ]
        append_optional(command, "--codex-path", args.codex_path)
        append_optional(command, "--codex-model", args.codex_model)
        append_optional(command, "--codex-profile", args.codex_profile)
        if args.skip_codex_preflight:
            command.append("--skip-codex-preflight")
        if args.dry_run:
            command.append("--dry-run")
        stage = run_stage("generate expected dataset", command, dry_run=args.dry_run)
        stages.append(stage)
        if stage["exitCode"] != 0:
            return finish(actual_output, stages, stage["exitCode"], args.dry_run)

    if not args.skip_run:
        command = [
            sys.executable,
            str(SCRIPT_DIR / "run_project_with_dataset.py"),
            "--package-dir",
            str(package_dir),
            "--dataset-path",
            str(dataset_output),
            "--output",
            str(actual_output),
            "--mode",
            args.mode,
            "--suite",
            args.suite,
            "--compare-traces",
            args.compare_traces,
            "--write-actual-traces",
            args.write_actual_traces,
            "--require-live-model",
            args.require_live_model,
            "--allow-evaluation-failures",
            args.allow_evaluation_failures,
        ]
        if args.dry_run:
            command.append("--dry-run")
        stage = run_stage("run project against dataset", command, dry_run=args.dry_run)
        stages.append(stage)
        if stage["exitCode"] != 0:
            return finish(actual_output, stages, stage["exitCode"], args.dry_run)

    if not args.skip_compare:
        command = [
            sys.executable,
            str(SCRIPT_DIR / "compare_expected_actual.py"),
            "--dataset-path",
            str(dataset_output),
            "--actual-output",
            str(actual_output),
        ]
        if args.fail_under_pass_rate is not None:
            command.extend(["--fail-under-pass-rate", str(args.fail_under_pass_rate)])
        stage = run_stage("compare expected and actual", command, dry_run=args.dry_run)
        stages.append(stage)
        if stage["exitCode"] != 0:
            return finish(actual_output, stages, stage["exitCode"], args.dry_run)

    return finish(actual_output, stages, 0, args.dry_run)


def finish(actual_output: Path, stages: list[dict[str, Any]], exit_code: int, dry_run: bool) -> int:
    record = {
        "startedAt": stages[0]["startedAt"] if stages else now_iso(),
        "completedAt": now_iso(),
        "exitCode": exit_code,
        "stages": stages,
    }
    if dry_run:
        print(json.dumps(record, indent=2, sort_keys=True))
        return exit_code
    actual_output.mkdir(parents=True, exist_ok=True)
    run_record = actual_output / "golden-pipeline-run.json"
    run_record.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"\nPipeline run record: {run_record}")
    return exit_code


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:  # noqa: BLE001 - keep CLI failures concise.
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
