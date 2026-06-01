#!/usr/bin/env python3
"""Compare generated golden expectations with actual evaluation artifacts.

The Swift evaluator already performs case-level assertions, trace-contract
comparison, and metrics-contract comparison. This script creates a higher-level
accuracy report that is easy to archive, diff, and read after a full dataset run.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable


REPO_ROOT = Path(__file__).resolve().parents[2]
PACKAGE_DIR = REPO_ROOT / "HomeAutomationCore"
DEFAULT_DATASET = PACKAGE_DIR / ".build" / "generated-evals" / "full-v1"
DEFAULT_ACTUAL_OUTPUT = PACKAGE_DIR / ".build" / "evaluation-full-v1"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Summarize golden dataset accuracy.")
    parser.add_argument("--dataset-path", type=Path, default=DEFAULT_DATASET)
    parser.add_argument("--actual-output", type=Path, default=DEFAULT_ACTUAL_OUTPUT)
    parser.add_argument("--output-json", type=Path)
    parser.add_argument("--output-md", type=Path)
    parser.add_argument("--fail-under-pass-rate", type=float)
    parser.add_argument(
        "--fail-on-missing-artifacts",
        choices=["true", "false"],
        default="true",
    )
    return parser.parse_args()


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"Expected object JSON in {path}")
    return value


def read_json_records(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    if not path.exists():
        return rows
    text = path.read_text(encoding="utf-8")
    decoder = json.JSONDecoder()
    index = 0
    length = len(text)
    while index < length:
        while index < length and text[index].isspace():
            index += 1
        if index >= length:
            break
        value, index = decoder.raw_decode(text, index)
        if not isinstance(value, dict):
            raise ValueError(f"Expected object JSON record in {path} near offset {index}")
        rows.append(value)
    return rows


def ratio(numerator: int, denominator: int) -> float:
    if denominator == 0:
        return 1.0
    return numerator / denominator


def pct(value: float) -> str:
    return f"{value * 100:.2f}%"


def expected_value(case: dict[str, Any], key: str) -> Any:
    expected = case.get("expected")
    if isinstance(expected, dict):
        return expected.get(key)
    return None


def result_matches(result: dict[str, Any], case: dict[str, Any], expected_key: str, actual_key: str) -> bool:
    expected = expected_value(case, expected_key)
    actual = result.get(actual_key)
    if expected is None:
        return True
    return expected == actual


def selected_device_matches(result: dict[str, Any], case: dict[str, Any]) -> bool:
    expected_devices = expected_value(case, "expectedDeviceIDs") or []
    actual_devices = result.get("selectedDeviceIDs") or []
    actual_target = result.get("actualTargetDeviceID")
    actual_set = set(actual_devices)
    if actual_target:
        actual_set.add(actual_target)
    return set(expected_devices).issubset(actual_set)


def group_pass_rates(results: Iterable[dict[str, Any]], key: str) -> dict[str, float]:
    totals: Counter[str] = Counter()
    passed: Counter[str] = Counter()
    for result in results:
        value = result.get(key)
        if not value:
            continue
        totals[str(value)] += 1
        if result.get("passed") is True:
            passed[str(value)] += 1
    return {name: ratio(passed[name], count) for name, count in sorted(totals.items())}


def tag_pass_rates(results: Iterable[dict[str, Any]]) -> dict[str, float]:
    totals: Counter[str] = Counter()
    passed: Counter[str] = Counter()
    for result in results:
        tags = result.get("tags") or []
        if not isinstance(tags, list):
            continue
        for tag in tags:
            tag_name = str(tag)
            totals[tag_name] += 1
            if result.get("passed") is True:
                passed[tag_name] += 1
    return {name: ratio(passed[name], count) for name, count in sorted(totals.items())}


def collect_artifacts(output: Path) -> dict[str, Any]:
    actual_traces = output / "actual-traces"
    trace_diffs = output / "trace-diffs"
    return {
        "evaluationResultsExists": (output / "evaluation-results.jsonl").exists(),
        "evaluationSummaryExists": (output / "evaluation-summary.json").exists(),
        "evaluationReportExists": (output / "evaluation-report.md").exists(),
        "agentMetricsExists": (output / "agent-metrics.json").exists(),
        "datasetValidationReportExists": (output / "dataset-validation-report.md").exists(),
        "actualTraceDirectoryExists": actual_traces.is_dir(),
        "traceDiffDirectoryExists": trace_diffs.is_dir(),
        "actualTraceFileCount": len(list(actual_traces.glob("*.jsonl"))) if actual_traces.is_dir() else 0,
        "traceDiffFileCount": len(list(trace_diffs.glob("*.json"))) if trace_diffs.is_dir() else 0,
    }


def missing_required_artifacts(artifacts: dict[str, Any]) -> list[str]:
    required_boolean_fields = [
        "evaluationResultsExists",
        "evaluationSummaryExists",
        "evaluationReportExists",
        "agentMetricsExists",
        "datasetValidationReportExists",
        "actualTraceDirectoryExists",
        "traceDiffDirectoryExists",
    ]
    return [field for field in required_boolean_fields if not artifacts.get(field)]


def build_accuracy_report(dataset_path: Path, actual_output: Path) -> dict[str, Any]:
    cases = read_json_records(dataset_path / "cases.jsonl")
    fixtures = read_json_records(dataset_path / "fixtures.jsonl")
    traces = read_json_records(dataset_path / "expected-traces.jsonl")
    metrics = read_json_records(dataset_path / "expected-metrics.jsonl")
    results = read_json_records(actual_output / "evaluation-results.jsonl")
    summary = read_json(actual_output / "evaluation-summary.json") if (actual_output / "evaluation-summary.json").exists() else {}
    agent_metrics = read_json(actual_output / "agent-metrics.json") if (actual_output / "agent-metrics.json").exists() else {}

    cases_by_id = {case["id"]: case for case in cases if "id" in case}
    results_by_id = {result["id"]: result for result in results if "id" in result}
    evaluated_ids = set(results_by_id)
    expected_ids = set(cases_by_id)
    shared_ids = sorted(expected_ids & evaluated_ids)
    missing_ids = sorted(expected_ids - evaluated_ids)
    unexpected_ids = sorted(evaluated_ids - expected_ids)

    shared_pairs = [(results_by_id[case_id], cases_by_id[case_id]) for case_id in shared_ids]
    passed_count = sum(1 for result in results if result.get("passed") is True)
    failed_count = sum(1 for result in results if result.get("passed") is False and not result.get("skipped"))
    skipped_count = sum(1 for result in results if result.get("skipped") is True)

    selected_device_count = sum(1 for result, case in shared_pairs if expected_value(case, "expectedDeviceIDs"))
    target_device_count = sum(1 for result, case in shared_pairs if expected_value(case, "targetDeviceID"))
    capability_count = sum(1 for result, case in shared_pairs if expected_value(case, "capability"))
    command_count = sum(1 for result, case in shared_pairs if expected_value(case, "command"))
    action_count_cases = sum(1 for result, case in shared_pairs if expected_value(case, "actionCount") is not None)
    condition_count_cases = sum(1 for result, case in shared_pairs if expected_value(case, "conditionCount") is not None)

    top_failures = []
    for result in results:
        if result.get("passed") is True:
            continue
        top_failures.append(
            {
                "id": result.get("id"),
                "suite": result.get("suite"),
                "fixtureID": result.get("fixtureID"),
                "status": result.get("status"),
                "assertionFailures": result.get("assertionFailures") or [],
            }
        )
        if len(top_failures) >= 25:
            break

    artifact_summary = collect_artifacts(actual_output)
    report = {
        "dataset": {
            "path": str(dataset_path),
            "fixtureCount": len(fixtures),
            "caseCount": len(cases),
            "expectedTraceContractCount": len(traces),
            "expectedMetricsContractCount": len(metrics),
        },
        "actual": {
            "path": str(actual_output),
            "evaluatedCaseCount": len(results),
            "passedCaseCount": passed_count,
            "failedCaseCount": failed_count,
            "skippedCaseCount": skipped_count,
            "passRate": ratio(passed_count, len(results)),
            "missingExpectedCaseCount": len(missing_ids),
            "unexpectedActualCaseCount": len(unexpected_ids),
        },
        "accuracy": {
            "selectedDeviceExactMatchAccuracy": ratio(
                sum(1 for result, case in shared_pairs if expected_value(case, "expectedDeviceIDs") and selected_device_matches(result, case)),
                selected_device_count,
            ),
            "targetDeviceExactMatchAccuracy": ratio(
                sum(1 for result, case in shared_pairs if result_matches(result, case, "targetDeviceID", "actualTargetDeviceID")),
                target_device_count,
            ),
            "capabilityExactMatchAccuracy": ratio(
                sum(1 for result, case in shared_pairs if result_matches(result, case, "capability", "actualCapability")),
                capability_count,
            ),
            "commandExactMatchAccuracy": ratio(
                sum(1 for result, case in shared_pairs if result_matches(result, case, "command", "actualCommand")),
                command_count,
            ),
            "automationActionCountAccuracy": ratio(
                sum(1 for result, case in shared_pairs if result_matches(result, case, "actionCount", "actualActionCount")),
                action_count_cases,
            ),
            "automationConditionCountAccuracy": ratio(
                sum(1 for result, case in shared_pairs if result_matches(result, case, "conditionCount", "actualConditionCount")),
                condition_count_cases,
            ),
            "agentTraceIdentityPassRate": summary.get("agentTraceIdentityPassRate"),
            "toolTraceIdentityPassRate": summary.get("toolTraceIdentityPassRate"),
            "contextWindowFailureRate": summary.get("contextWindowFailureRate"),
        },
        "budgets": {
            "totalModelCallCount": sum(int(result.get("modelCallCount") or 0) for result in results),
            "totalToolCallCount": sum(int(result.get("toolCallCount") or 0) for result in results),
            "averageModelCallsPerCase": ratio(sum(int(result.get("modelCallCount") or 0) for result in results), len(results)),
            "averageToolCallsPerCase": ratio(sum(int(result.get("toolCallCount") or 0) for result in results), len(results)),
        },
        "groups": {
            "passRateBySuite": group_pass_rates(results, "suite"),
            "passRateByFixture": group_pass_rates(results, "fixtureID"),
            "passRateByTag": tag_pass_rates(results),
        },
        "artifacts": artifact_summary,
        "missingExpectedCaseIDs": missing_ids[:100],
        "unexpectedActualCaseIDs": unexpected_ids[:100],
        "topFailingCases": top_failures,
        "agentMetrics": agent_metrics,
    }
    return report


def write_markdown(report: dict[str, Any], output_md: Path) -> None:
    dataset = report["dataset"]
    actual = report["actual"]
    accuracy = report["accuracy"]
    budgets = report["budgets"]
    artifacts = report["artifacts"]
    lines = [
        "# Golden Evaluation Accuracy Report",
        "",
        "## Summary",
        "",
        f"- Dataset: `{dataset['path']}`",
        f"- Actual output: `{actual['path']}`",
        f"- Fixtures: {dataset['fixtureCount']}",
        f"- Expected cases: {dataset['caseCount']}",
        f"- Evaluated cases: {actual['evaluatedCaseCount']}",
        f"- Pass rate: {pct(actual['passRate'])}",
        f"- Failed cases: {actual['failedCaseCount']}",
        f"- Skipped cases: {actual['skippedCaseCount']}",
        f"- Missing expected cases: {actual['missingExpectedCaseCount']}",
        "",
        "## Accuracy",
        "",
        "| Metric | Value |",
        "|---|---:|",
        f"| Selected device exact match | {pct(accuracy['selectedDeviceExactMatchAccuracy'])} |",
        f"| Target device exact match | {pct(accuracy['targetDeviceExactMatchAccuracy'])} |",
        f"| Capability exact match | {pct(accuracy['capabilityExactMatchAccuracy'])} |",
        f"| Command exact match | {pct(accuracy['commandExactMatchAccuracy'])} |",
        f"| Automation action count | {pct(accuracy['automationActionCountAccuracy'])} |",
        f"| Automation condition count | {pct(accuracy['automationConditionCountAccuracy'])} |",
    ]
    if accuracy.get("agentTraceIdentityPassRate") is not None:
        lines.append(f"| Agent trace identity | {pct(float(accuracy['agentTraceIdentityPassRate']))} |")
    if accuracy.get("toolTraceIdentityPassRate") is not None:
        lines.append(f"| Tool trace identity | {pct(float(accuracy['toolTraceIdentityPassRate']))} |")
    if accuracy.get("contextWindowFailureRate") is not None:
        lines.append(f"| Context-window failure rate | {pct(float(accuracy['contextWindowFailureRate']))} |")

    lines.extend(
        [
            "",
            "## Budgets",
            "",
            "| Metric | Value |",
            "|---|---:|",
            f"| Total model calls | {budgets['totalModelCallCount']} |",
            f"| Average model calls per case | {budgets['averageModelCallsPerCase']:.2f} |",
            f"| Total tool calls | {budgets['totalToolCallCount']} |",
            f"| Average tool calls per case | {budgets['averageToolCallsPerCase']:.2f} |",
            "",
            "## Artifact Check",
            "",
            "| Artifact | Value |",
            "|---|---:|",
        ]
    )
    for key, value in artifacts.items():
        lines.append(f"| {key} | {value} |")

    lines.extend(["", "## Pass Rate By Suite", "", "| Suite | Pass rate |", "|---|---:|"])
    for suite, value in report["groups"]["passRateBySuite"].items():
        lines.append(f"| {suite} | {pct(value)} |")

    lines.extend(["", "## Top Failing Cases", "", "| Case | Suite | Fixture | Failures |", "|---|---|---|---|"])
    for failure in report["topFailingCases"][:20]:
        failures = "; ".join(str(item) for item in failure.get("assertionFailures", []))
        lines.append(f"| {failure.get('id')} | {failure.get('suite')} | {failure.get('fixtureID')} | {failures} |")

    output_md.parent.mkdir(parents=True, exist_ok=True)
    output_md.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    dataset_path = args.dataset_path.resolve()
    actual_output = args.actual_output.resolve()
    output_json = (args.output_json or (actual_output / "golden-accuracy-report.json")).resolve()
    output_md = (args.output_md or (actual_output / "golden-accuracy-report.md")).resolve()

    report = build_accuracy_report(dataset_path, actual_output)
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(report, output_md)

    print(
        json.dumps(
            {
                "accuracyReport": str(output_json),
                "markdownReport": str(output_md),
                "passRate": report["actual"]["passRate"],
                "evaluatedCaseCount": report["actual"]["evaluatedCaseCount"],
                "failedCaseCount": report["actual"]["failedCaseCount"],
            },
            indent=2,
            sort_keys=True,
        )
    )

    missing_artifacts = missing_required_artifacts(report["artifacts"])
    if args.fail_on_missing_artifacts == "true" and missing_artifacts:
        print(f"error: missing required artifacts: {', '.join(missing_artifacts)}", file=sys.stderr)
        return 1

    if args.fail_under_pass_rate is not None and report["actual"]["passRate"] < args.fail_under_pass_rate:
        print(
            f"error: pass rate {report['actual']['passRate']:.4f} is below "
            f"{args.fail_under_pass_rate:.4f}",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:  # noqa: BLE001 - keep CLI failures concise.
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
