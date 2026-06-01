#!/usr/bin/env python3
"""Generate a golden evaluation dataset through the Swift evaluation CLI.

Codex CLI generation is the default because expected labels remain deterministic
inside the HomeAutomationEvaluation generator while Codex only paraphrases user
commands.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
PACKAGE_DIR = REPO_ROOT / "HomeAutomationCore"
DEFAULT_OUTPUT = PACKAGE_DIR / ".build" / "generated-evals" / "full-v1"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a generated golden dataset.")
    parser.add_argument("--project-root", type=Path, default=REPO_ROOT)
    parser.add_argument("--package-dir", type=Path, default=PACKAGE_DIR)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--dataset-name", default="full-v1")
    parser.add_argument("--fixture-limit", type=int, default=100)
    parser.add_argument("--case-limit", type=int, default=10_000)
    parser.add_argument(
        "--generation-mode",
        choices=["codex", "template", "foundation-model"],
        default="codex",
    )
    parser.add_argument("--codex-path", default=os.environ.get("HOME_AUTOMATION_EVAL_CODEX_PATH"))
    parser.add_argument("--codex-model", default=os.environ.get("HOME_AUTOMATION_EVAL_CODEX_MODEL"))
    parser.add_argument("--codex-profile", default=os.environ.get("HOME_AUTOMATION_EVAL_CODEX_PROFILE"))
    parser.add_argument("--skip-codex-preflight", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def run_command(command: list[str], cwd: Path, env: dict[str, str], dry_run: bool) -> None:
    print("+", " ".join(command))
    if dry_run:
        return
    subprocess.run(command, cwd=cwd, env=env, check=True)


def read_json_records(path: Path) -> list[Any]:
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8")
    decoder = json.JSONDecoder()
    records: list[Any] = []
    index = 0
    length = len(text)
    while index < length:
        while index < length and text[index].isspace():
            index += 1
        if index >= length:
            break
        value, index = decoder.raw_decode(text, index)
        records.append(value)
    return records


def count_json_records(path: Path) -> int:
    if not path.exists():
        return 0
    return len(read_json_records(path))


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"Expected object JSON in {path}")
    return value


def validate_dataset(output: Path, expected_fixture_count: int, expected_case_count: int) -> None:
    required_files = [
        "manifest.json",
        "fixtures.jsonl",
        "cases.jsonl",
        "expected-traces.jsonl",
        "expected-metrics.jsonl",
        "dataset-validation-report.md",
    ]
    missing = [name for name in required_files if not (output / name).exists()]
    if missing:
        raise RuntimeError(f"Generated dataset is missing required files: {', '.join(missing)}")

    manifest = load_json(output / "manifest.json")
    fixture_count = count_json_records(output / "fixtures.jsonl")
    case_count = count_json_records(output / "cases.jsonl")
    trace_count = count_json_records(output / "expected-traces.jsonl")
    metric_count = count_json_records(output / "expected-metrics.jsonl")

    if fixture_count != expected_fixture_count:
        raise RuntimeError(f"Expected {expected_fixture_count} fixtures, found {fixture_count}")
    if case_count != expected_case_count:
        raise RuntimeError(f"Expected {expected_case_count} cases, found {case_count}")
    if trace_count != case_count or metric_count != case_count:
        raise RuntimeError(
            "Trace/metrics contract counts must match cases: "
            f"cases={case_count}, traces={trace_count}, metrics={metric_count}"
        )
    if manifest.get("validationStatus") != "passed":
        raise RuntimeError(f"Dataset validation did not pass: {manifest.get('validationStatus')}")

    print(
        json.dumps(
            {
                "dataset": str(output),
                "manifestName": manifest.get("name"),
                "generationMode": manifest.get("generationMode"),
                "fixtures": fixture_count,
                "cases": case_count,
                "traceContracts": trace_count,
                "metricsContracts": metric_count,
            },
            indent=2,
            sort_keys=True,
        )
    )


def main() -> int:
    args = parse_args()
    package_dir = args.package_dir.resolve()
    output = args.output.resolve()
    env = os.environ.copy()

    if args.codex_path:
        env["HOME_AUTOMATION_EVAL_CODEX_PATH"] = args.codex_path
    if args.codex_model:
        env["HOME_AUTOMATION_EVAL_CODEX_MODEL"] = args.codex_model
    if args.codex_profile:
        env["HOME_AUTOMATION_EVAL_CODEX_PROFILE"] = args.codex_profile

    if args.generation_mode == "codex" and not args.skip_codex_preflight and not args.dry_run:
        codex_binary = args.codex_path or shutil.which("codex")
        if not codex_binary:
            raise RuntimeError(
                "Codex generation requested, but no codex executable was found. "
                "Install Codex CLI, set HOME_AUTOMATION_EVAL_CODEX_PATH, or use "
                "--generation-mode template for deterministic local generation."
            )

    command = [
        "swift",
        "run",
        "home-automation-eval",
        "--generate-dataset",
        "true",
        "--generation-mode",
        args.generation_mode,
        "--dataset",
        args.dataset_name,
        "--fixture-limit",
        str(args.fixture_limit),
        "--case-limit",
        str(args.case_limit),
        "--output",
        str(output),
    ]
    run_command(command, cwd=package_dir, env=env, dry_run=args.dry_run)
    if not args.dry_run:
        validate_dataset(output, args.fixture_limit, args.case_limit)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:  # noqa: BLE001 - script should print concise operational failures.
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
