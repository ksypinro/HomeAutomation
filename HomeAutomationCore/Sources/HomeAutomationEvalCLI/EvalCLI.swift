import Foundation
import HomeAutomationEvaluation

@main
struct HomeAutomationEvalCLI {
    static func main() async throws {
        let options = try EvaluationCLIOptions.parse(CommandLine.arguments.dropFirst())
        let runner = EvaluationRunner(
            mode: options.mode,
            requireLiveModel: options.requireLiveModel,
            suites: options.suites
        )
        let result = await runner.run()
        try runner.write(result, to: options.outputURL)

        print("Home automation evaluation \(result.summary.passedCaseCount)/\(result.summary.totalCaseCount) passed")
        print("Report: \(options.outputURL.appendingPathComponent("evaluation-report.md").path)")

        if result.summary.failedCaseCount > 0 {
            throw EvaluationCLIError.failedCases(result.summary.failedCaseCount)
        }
    }
}

private struct EvaluationCLIOptions {
    let mode: EvaluationMode
    let suites: Set<String>
    let outputURL: URL
    let requireLiveModel: Bool

    static func parse(_ arguments: ArraySlice<String>) throws -> EvaluationCLIOptions {
        var mode: EvaluationMode = .deterministic
        var suites: Set<String> = ["all"]
        var output = ".build/evaluation"
        var requireLiveModel = false
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
                requireLiveModel = ["1", "true", "yes", "on"].contains(value.lowercased())
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
            requireLiveModel: requireLiveModel
        )
    }

    private static let help = """
    Usage:
      swift run home-automation-eval --mode deterministic --suite all --output .build/evaluation
      HOME_AUTOMATION_EVAL_LIVE=1 swift run home-automation-eval --mode live --suite all --require-live-model true --output .build/evaluation-live
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
