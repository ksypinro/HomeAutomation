import Foundation
import FoundationModels

public enum FoundationModelTokenEstimatorSource: String, Sendable, Codable, Equatable {
    case conservativeHeuristic
    case native
}

public struct HomeModelContextBudgetReport: Sendable, Codable, Equatable {
    public let estimatedInputTokenCount: Int
    public let maxContextSize: Int
    public let promptCharacterCount: Int
    public let toolCount: Int
    public let candidateCount: Int
    public let ragCapabilitySectionCount: Int
    public let ragExampleSectionCount: Int
    public let ragBixbySectionCount: Int
    public let selectedCompactionLevel: String
    public let selectedToolNames: [String]
    public let estimatedToolOutputCharacterCount: Int
    public let tokenEstimatorSource: FoundationModelTokenEstimatorSource

    public init(
        estimatedInputTokenCount: Int,
        maxContextSize: Int,
        promptCharacterCount: Int,
        toolCount: Int,
        candidateCount: Int,
        ragCapabilitySectionCount: Int,
        ragExampleSectionCount: Int,
        ragBixbySectionCount: Int,
        selectedCompactionLevel: String,
        selectedToolNames: [String] = [],
        estimatedToolOutputCharacterCount: Int = 0,
        tokenEstimatorSource: FoundationModelTokenEstimatorSource = .conservativeHeuristic
    ) {
        self.estimatedInputTokenCount = estimatedInputTokenCount
        self.maxContextSize = maxContextSize
        self.promptCharacterCount = promptCharacterCount
        self.toolCount = toolCount
        self.candidateCount = candidateCount
        self.ragCapabilitySectionCount = ragCapabilitySectionCount
        self.ragExampleSectionCount = ragExampleSectionCount
        self.ragBixbySectionCount = ragBixbySectionCount
        self.selectedCompactionLevel = selectedCompactionLevel
        self.selectedToolNames = selectedToolNames
        self.estimatedToolOutputCharacterCount = estimatedToolOutputCharacterCount
        self.tokenEstimatorSource = tokenEstimatorSource
    }
}

public struct FoundationModelContextBudgeter: Sendable {
    public let maxContextSize: Int
    public let reservedTokenCount: Int
    public let tokenEstimatorSource: FoundationModelTokenEstimatorSource

    public init(
        maxContextSize: Int = 4_096,
        reservedTokenCount: Int = 896,
        tokenEstimatorSource: FoundationModelTokenEstimatorSource = .conservativeHeuristic
    ) {
        self.maxContextSize = maxContextSize
        self.reservedTokenCount = reservedTokenCount
        self.tokenEstimatorSource = tokenEstimatorSource
    }

    public var promptTokenBudget: Int {
        max(512, maxContextSize - reservedTokenCount)
    }

    public func estimateTokenCount(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        var estimate = 0
        var asciiWordCharacterCount = 0

        func flushASCIIWord() {
            guard asciiWordCharacterCount > 0 else { return }
            estimate += max(1, Int(ceil(Double(asciiWordCharacterCount) / 3.6)))
            asciiWordCharacterCount = 0
        }

        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                flushASCIIWord()
            } else if scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) {
                asciiWordCharacterCount += 1
            } else {
                flushASCIIWord()
                if scalar.isASCII {
                    estimate += punctuationTokenCost(for: scalar)
                } else {
                    estimate += 1
                }
            }
        }

        flushASCIIWord()
        return max(1, estimate)
    }

    private func punctuationTokenCost(for scalar: UnicodeScalar) -> Int {
        switch scalar {
        case "{", "}", "[", "]", ":", ",", "\"", "\\", "/", ".", "-", "_", "=":
            return 1
        default:
            return 1
        }
    }

    public func report(
        instructionText: String,
        prompt: String,
        tools: [any Tool],
        candidateCount: Int,
        ragCapabilitySectionCount: Int,
        ragExampleSectionCount: Int,
        ragBixbySectionCount: Int,
        selectedCompactionLevel: String,
        estimatedToolOutputCharacterCount: Int = 0
    ) -> HomeModelContextBudgetReport {
        let toolDescriptorText = tools
            .map { "\($0.name): \($0.description)" }
            .joined(separator: "\n")
        let estimatedInputTokens =
            estimateTokenCount(instructionText) +
            estimateTokenCount(prompt) +
            estimateTokenCount(toolDescriptorText) +
            estimateTokenCount(String(repeating: "x", count: estimatedToolOutputCharacterCount))

        return HomeModelContextBudgetReport(
            estimatedInputTokenCount: estimatedInputTokens,
            maxContextSize: maxContextSize,
            promptCharacterCount: prompt.count,
            toolCount: tools.count,
            candidateCount: candidateCount,
            ragCapabilitySectionCount: ragCapabilitySectionCount,
            ragExampleSectionCount: ragExampleSectionCount,
            ragBixbySectionCount: ragBixbySectionCount,
            selectedCompactionLevel: selectedCompactionLevel,
            selectedToolNames: tools.map(\.name),
            estimatedToolOutputCharacterCount: estimatedToolOutputCharacterCount,
            tokenEstimatorSource: tokenEstimatorSource
        )
    }

    public func isWithinBudget(_ report: HomeModelContextBudgetReport) -> Bool {
        report.estimatedInputTokenCount <= promptTokenBudget
    }
}
