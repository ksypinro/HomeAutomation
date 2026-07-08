import Foundation
import HomeAutomationCore
import HomeAutomationEvaluation
import HomeAutomationOrchestrator

@main
struct HomeAutomationEvalCLI {
    static func main() async throws {
        let options = try EvaluationCLIOptions.parse(CommandLine.arguments.dropFirst())

        if options.compareOrchestration {
            try await runCompareOrchestration(options: options)
            return
        }

        if options.shadowVerify {
            try await runShadowVerify(options: options)
            return
        }

        if options.generateDataset {
            let fixtureLimit = options.fixtureLimit ?? 10
            let commandsPerFixture = options.caseLimit.map { max(1, $0 / max(fixtureLimit, 1)) } ?? 100
            let datasetName = options.dataset ?? defaultGeneratedDatasetName(
                fixtureLimit: fixtureLimit,
                commandsPerFixture: commandsPerFixture
            )
            let generator = EvaluationCommandGenerator(
                paraphraseProvider: makeParaphraseProvider(for: options.generationMode),
                generationMode: options.generationMode
            )
            let dataset = try await generator.generateDataset(
                name: datasetName,
                fixtureLimit: fixtureLimit,
                commandsPerFixture: commandsPerFixture
            )
            try EvaluationDatasetWriter().write(dataset, to: options.outputURL)
            print("Generated dataset \(dataset.manifest.name): \(dataset.fixtures.count) fixture(s), \(dataset.cases.count) case(s)")
            print("Generation mode: \(dataset.manifest.generationMode)")
            print("Dataset: \(options.outputURL.path)")
            return
        }

        let runner = EvaluationRunner(
            mode: options.mode,
            requireLiveModel: options.requireLiveModel,
            suites: options.suites
        )
        let result: EvaluationSuiteResult
        if let dataset = try options.loadDatasetIfRequested() {
            result = await runner.runGeneratedDataset(
                dataset,
                compareTraces: options.compareTraces,
                writeActualTraces: options.writeActualTraces,
                outputURL: options.outputURL,
                caseLimit: options.caseLimit,
                fixtureLimit: options.fixtureLimit
            )
        } else {
            result = await runner.run()
        }
        try runner.write(result, to: options.outputURL)

        print("Home automation evaluation \(result.summary.passedCaseCount)/\(result.summary.totalCaseCount) passed")
        print("Report: \(options.outputURL.appendingPathComponent("evaluation-report.md").path)")

        if result.summary.failedCaseCount > 0 {
            throw EvaluationCLIError.failedCases(result.summary.failedCaseCount)
        }
    }

    private static func defaultGeneratedDatasetName(
        fixtureLimit: Int,
        commandsPerFixture: Int
    ) -> String {
        fixtureLimit > 10 || commandsPerFixture > 100 ? "full-v1" : "seed-v1"
    }

    private static func runCompareOrchestration(options: EvaluationCLIOptions) async throws {
        let runner = OrchestrationComparisonRunner(
            caseLimit: options.caseLimit,
            requireLiveModel: options.requireLiveModel
        )
        let report = await runner.run()
        try OrchestrationComparisonRunner.writeReport(report, to: options.outputURL)

        print("Orchestration comparison: \(report.caseCount) case(s) across \(report.armSummaries.count) arm(s) [\(options.requireLiveModel ? "live model" : "deterministic")]")
        for summary in report.armSummaries {
            print("  \(summary.arm.rawValue): accuracy=\(String(format: "%.1f%%", summary.accuracy * 100)), meanFM=\(String(format: "%.2f", summary.meanFMCalls)), p95=\(String(format: "%.1fms", summary.p95DurationMs))")
        }
        let passCount = report.exitCriteriaResults.filter(\.passed).count
        let totalCount = report.exitCriteriaResults.count
        print("Exit criteria: \(passCount)/\(totalCount) passed")
        print("Report: \(options.outputURL.appendingPathComponent("orchestration-comparison.md").path)")

        if passCount < totalCount {
            throw EvaluationCLIError.failedCases(totalCount - passCount)
        }
    }

    private static func runShadowVerify(options: EvaluationCLIOptions) async throws {
        let registry = DeviceCoordinator.makeMockDeviceRegistry()
        let runner = VerifierShadowRunner(registry: registry)
        let cases = EvaluationCorpus.defaultCases
        let report = await runner.run(
            cases: cases,
            caseLimit: options.caseLimit
        )
        try VerifierShadowRunner.writeReport(report, to: options.outputURL)

        print("Verifier shadow evaluation: \(report.verifiedCases)/\(report.totalCases) verified, \(report.skippedCases) skipped")
        print("Accept rate: \(String(format: "%.1f%%", report.acceptRate * 100))")
        print("False-accept rate: \(String(format: "%.1f%%", report.falseAcceptRate * 100))")
        print("False-reject rate: \(String(format: "%.1f%%", report.falseRejectRate * 100))")
        print("Report: \(options.outputURL.appendingPathComponent("verifier-shadow-report.json").path)")
    }

    private static func makeParaphraseProvider(
        for mode: EvaluationCommandGenerationMode
    ) -> any CommandParaphraseProvider {
        switch mode {
        case .codex:
            return CodexCLICommandParaphraseProvider()
        case .template:
            return TemplateCommandParaphraseProvider()
        case .foundationModel:
            return FoundationModelCommandParaphraseProvider()
        }
    }
}

private struct EvaluationCLIOptions {
    let mode: EvaluationMode
    let suites: Set<String>
    let outputURL: URL
    let requireLiveModel: Bool
    let dataset: String?
    let datasetPath: String?
    let compareTraces: Bool
    let writeActualTraces: Bool
    let caseLimit: Int?
    let fixtureLimit: Int?
    let generateDataset: Bool
    let generationMode: EvaluationCommandGenerationMode
    let shadowVerify: Bool
    let compareOrchestration: Bool

    static func parse(_ arguments: ArraySlice<String>) throws -> EvaluationCLIOptions {
        var mode: EvaluationMode = .deterministic
        var suites: Set<String> = ["all"]
        var output = ".build/evaluation"
        var requireLiveModel = false
        var dataset: String?
        var datasetPath: String?
        var compareTraces = false
        var writeActualTraces = false
        var caseLimit: Int?
        var fixtureLimit: Int?
        var generateDataset = false
        var generationMode: EvaluationCommandGenerationMode = .codex
        var shadowVerify = false
        var compareOrchestration = false
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--mode":
                guard let value = iterator.next(), let parsed = EvaluationMode(rawValue: value) else {
                    throw EvaluationCLIError.invalidArgument("--mode")
                }
                mode = parsed
            case "--suite":
                guard let value = iterator.next(), !value.isEmpty else {
                    throw EvaluationCLIError.invalidArgument("--suite")
                }
                suites = Set(value.split(separator: ",").map(String.init))
            case "--output":
                guard let value = iterator.next(), !value.isEmpty else {
                    throw EvaluationCLIError.invalidArgument("--output")
                }
                output = value
            case "--require-live-model":
                guard let value = iterator.next() else {
                    throw EvaluationCLIError.invalidArgument("--require-live-model")
                }
                requireLiveModel = parseBool(value)
            case "--dataset":
                guard let value = iterator.next(), !value.isEmpty else {
                    throw EvaluationCLIError.invalidArgument("--dataset")
                }
                dataset = value
            case "--dataset-path":
                guard let value = iterator.next(), !value.isEmpty else {
                    throw EvaluationCLIError.invalidArgument("--dataset-path")
                }
                datasetPath = value
            case "--compare-traces":
                guard let value = iterator.next() else {
                    throw EvaluationCLIError.invalidArgument("--compare-traces")
                }
                compareTraces = parseBool(value)
            case "--write-actual-traces":
                guard let value = iterator.next() else {
                    throw EvaluationCLIError.invalidArgument("--write-actual-traces")
                }
                writeActualTraces = parseBool(value)
            case "--case-limit":
                guard let value = iterator.next(), let parsed = Int(value), parsed > 0 else {
                    throw EvaluationCLIError.invalidArgument("--case-limit")
                }
                caseLimit = parsed
            case "--fixture-limit":
                guard let value = iterator.next(), let parsed = Int(value), parsed > 0 else {
                    throw EvaluationCLIError.invalidArgument("--fixture-limit")
                }
                fixtureLimit = parsed
            case "--generate-dataset":
                guard let value = iterator.next() else {
                    throw EvaluationCLIError.invalidArgument("--generate-dataset")
                }
                generateDataset = parseBool(value)
            case "--generation-mode":
                guard let value = iterator.next(), let parsed = parseGenerationMode(value) else {
                    throw EvaluationCLIError.invalidArgument("--generation-mode")
                }
                generationMode = parsed
            case "--shadow-verify":
                shadowVerify = true
            case "--compare-orchestration":
                compareOrchestration = true
            case "--help", "-h":
                print(Self.help)
                Foundation.exit(0)
            default:
                throw EvaluationCLIError.invalidArgument(argument)
            }
        }

        return EvaluationCLIOptions(
            mode: mode,
            suites: suites,
            outputURL: URL(fileURLWithPath: output, isDirectory: true),
            requireLiveModel: requireLiveModel,
            dataset: dataset,
            datasetPath: datasetPath,
            compareTraces: compareTraces,
            writeActualTraces: writeActualTraces,
            caseLimit: caseLimit,
            fixtureLimit: fixtureLimit,
            generateDataset: generateDataset,
            generationMode: generationMode,
            shadowVerify: shadowVerify,
            compareOrchestration: compareOrchestration
        )
    }

    func loadDatasetIfRequested() throws -> GeneratedEvaluationDataset? {
        let loader = EvaluationDatasetResourceLoader()
        if let datasetPath {
            return try loader.loadExternalDataset(from: URL(fileURLWithPath: datasetPath, isDirectory: true))
        }
        if let dataset {
            return try loader.loadBuiltInDataset(named: dataset)
        }
        return nil
    }

    private static func parseBool(_ value: String) -> Bool {
        ["1", "true", "yes", "on"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private static func parseGenerationMode(_ value: String) -> EvaluationCommandGenerationMode? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "codex", "codex-cli", "codex_cli":
            return .codex
        case "template":
            return .template
        case "foundationmodel", "foundation-model", "foundation_model", "live":
            return .foundationModel
        default:
            return nil
        }
    }

    private static let help = """
    Usage:
      swift run home-automation-eval --mode deterministic --suite all --output .build/evaluation
      HOME_AUTOMATION_EVAL_LIVE=1 swift run home-automation-eval --mode live --suite all --require-live-model true --output .build/evaluation-live
      swift run home-automation-eval --mode deterministic --dataset seed-v1 --compare-traces true --write-actual-traces true --output .build/evaluation-seed
      swift run home-automation-eval --generate-dataset true --generation-mode codex --fixture-limit 10 --case-limit 1000 --output .build/generated-evals/seed-v1
      swift run home-automation-eval --generate-dataset true --generation-mode template --fixture-limit 10 --case-limit 1000 --output .build/generated-evals/seed-v1-template
      swift run home-automation-eval --generate-dataset true --generation-mode foundation-model --fixture-limit 10 --case-limit 1000 --output .build/generated-evals/seed-v1-live
      swift run home-automation-eval --shadow-verify --output .build/evaluation-shadow --case-limit 50
      swift run home-automation-eval --compare-orchestration --output .build/evaluation-comparison --case-limit 50
      HOME_AUTOMATION_EVAL_LIVE=1 swift run home-automation-eval --compare-orchestration --require-live-model true --output .build/evaluation-comparison-live
    """
}

private enum EvaluationCLIError: Error, CustomStringConvertible {
    case invalidArgument(String)
    case failedCases(Int)

    var description: String {
        switch self {
        case .invalidArgument(let argument):
            return "Invalid evaluation CLI argument: \(argument)"
        case .failedCases(let count):
            return "\(count) evaluation case(s) failed"
        }
    }
}
