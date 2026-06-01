#!/usr/bin/env python3
"""Run the HomeAutomation evaluation CLI against a generated dataset.

This stage produces the actual project outputs: case results, summaries,
per-agent metrics, actual traces, and trace diffs.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
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
    parser = argparse.ArgumentParser(description="Run project evaluation for a generated dataset.")
    parser.add_argument("--package-dir", type=Path, default=PACKAGE_DIR)
    parser.add_argument("--dataset-path", type=Path, default=DEFAULT_DATASET)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--mode", choices=["deterministic", "live"], default="deterministic")
    parser.add_argument("--suite", default="all")
    parser.add_argument("--case-limit", type=int)
    parser.add_argument("--fixture-limit", type=int)
    parser.add_argument("--compare-traces", type=parse_bool, default="true")
    parser.add_argument("--write-actual-traces", type=parse_bool, default="true")
    parser.add_argument("--require-live-model", type=parse_bool, default="false")
    parser.add_argument(
        "--allow-evaluation-failures",
        type=parse_bool,
        default="true",
        help="Keep the pipeline moving when the Swift evaluator reports failed cases but still writes artifacts.",
    )
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"Expected object JSON in {path}")
    return value


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
    return len(read_json_records(path))


def validate_dataset_path(dataset_path: Path) -> None:
    required = [
        "manifest.json",
        "fixtures.jsonl",
        "cases.jsonl",
        "expected-traces.jsonl",
        "expected-metrics.jsonl",
    ]
    missing = [name for name in required if not (dataset_path / name).exists()]
    if missing:
        raise RuntimeError(f"Dataset path {dataset_path} is missing: {', '.join(missing)}")

    manifest = load_json(dataset_path / "manifest.json")
    case_count = count_json_records(dataset_path / "cases.jsonl")
    if case_count == 0:
        raise RuntimeError(f"Dataset path {dataset_path} contains no cases")

    print(
        json.dumps(
            {
                "datasetPath": str(dataset_path),
                "datasetName": manifest.get("name"),
                "generationMode": manifest.get("generationMode"),
                "fixtures": count_json_records(dataset_path / "fixtures.jsonl"),
                "cases": case_count,
            },
            indent=2,
            sort_keys=True,
        )
    )


def validate_output(output: Path) -> None:
    required_files = [
        "evaluation-results.jsonl",
        "evaluation-summary.json",
        "evaluation-report.md",
        "agent-metrics.json",
        "dataset-validation-report.md",
    ]
    required_dirs = ["actual-traces", "trace-diffs"]
    missing_files = [name for name in required_files if not (output / name).exists()]
    missing_dirs = [name for name in required_dirs if not (output / name).is_dir()]
    if missing_files or missing_dirs:
        problems = [f"file:{name}" for name in missing_files] + [f"dir:{name}" for name in missing_dirs]
        raise RuntimeError(f"Evaluation output is missing required artifacts: {', '.join(problems)}")

    summary = load_json(output / "evaluation-summary.json")
    result_count = count_json_records(output / "evaluation-results.jsonl")
    print(
        json.dumps(
            {
                "evaluationOutput": str(output),
                "results": result_count,
                "passRate": summary.get("passRate"),
                "failedCaseCount": summary.get("failedCaseCount"),
                "actualTraceFiles": len(list((output / "actual-traces").glob("*.jsonl"))),
                "traceDiffFiles": len(list((output / "trace-diffs").glob("*.json"))),
            },
            indent=2,
            sort_keys=True,
        )
    )


def run_command(command: list[str], cwd: Path, dry_run: bool) -> subprocess.CompletedProcess[str]:
    print("+", " ".join(command))
    if dry_run:
        return subprocess.CompletedProcess(command, 0, "", "")
    return subprocess.run(command, cwd=cwd, text=True, check=False)


def main() -> int:
    args = parse_args()
    package_dir = args.package_dir.resolve()
    dataset_path = args.dataset_path.resolve()
    output = args.output.resolve()

    if not args.dry_run:
        validate_dataset_path(dataset_path)

    command = [
        "swift",
        "run",
        "home-automation-eval",
        "--mode",
        args.mode,
        "--suite",
        args.suite,
        "--dataset-path",
        str(dataset_path),
        "--compare-traces",
        args.compare_traces,
        "--write-actual-traces",
        args.write_actual_traces,
        "--require-live-model",
        args.require_live_model,
        "--output",
        str(output),
    ]
    if args.case_limit is not None:
        command.extend(["--case-limit", str(args.case_limit)])
    if args.fixture_limit is not None:
        command.extend(["--fixture-limit", str(args.fixture_limit)])

    completed = run_command(command, cwd=package_dir, dry_run=args.dry_run)
    if args.dry_run:
        return 0

    if completed.returncode != 0:
        has_results = (output / "evaluation-results.jsonl").exists()
        if args.allow_evaluation_failures == "true" and has_results:
            print(
                "warning: Swift evaluator returned non-zero because one or more cases failed; "
                "continuing because artifacts were produced.",
                file=sys.stderr,
            )
        else:
            return completed.returncode

    validate_output(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:  # noqa: BLE001 - operational script should keep errors concise.
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
