import Foundation
import HomeAutomationCore
import HomeAutomationOrchestrator

public struct PortfolioRouterEvaluationCase: Sendable, Codable, Hashable {
    public let caseID: String
    public let selectedArm: FoundationModelCallArm
    public let oracleArm: FoundationModelCallArm
    public let selectedUtility: Double
    public let oracleUtility: Double
    public let regret: Double
    public let rejectedReason: String?

    public init(
        caseID: String,
        selectedArm: FoundationModelCallArm,
        oracleArm: FoundationModelCallArm,
        selectedUtility: Double,
        oracleUtility: Double,
        regret: Double,
        rejectedReason: String? = nil
    ) {
        self.caseID = caseID
        self.selectedArm = selectedArm
        self.oracleArm = oracleArm
        self.selectedUtility = selectedUtility
        self.oracleUtility = oracleUtility
        self.regret = max(0, regret)
        self.rejectedReason = rejectedReason
    }
}

public struct PortfolioRouterSliceSummary: Sendable, Codable, Hashable {
    public let name: String
    public let caseCount: Int
    public let meanRegret: Double
    public let maxRegret: Double

    public init(name: String, regrets: [Double]) {
        self.name = name
        self.caseCount = regrets.count
        self.meanRegret = regrets.isEmpty ? 0 : regrets.reduce(0, +) / Double(regrets.count)
        self.maxRegret = regrets.max() ?? 0
    }
}

public struct PortfolioRouterEvaluationReport: Sendable, Codable, Hashable {
    public let generatedAt: Date
    public let datasetID: String
    public let modelVersion: String
    public let caseCount: Int
    public let meanRegret: Double
    public let maxRegret: Double
    public let unsafeSelectionCount: Int
    public let cases: [PortfolioRouterEvaluationCase]
    public let slices: [PortfolioRouterSliceSummary]

    public init(
        generatedAt: Date = Date(),
        datasetID: String,
        modelVersion: String,
        cases: [PortfolioRouterEvaluationCase],
        slices: [PortfolioRouterSliceSummary]
    ) {
        self.generatedAt = generatedAt
        self.datasetID = datasetID
        self.modelVersion = modelVersion
        self.caseCount = cases.count
        self.meanRegret = cases.isEmpty ? 0 : cases.map(\.regret).reduce(0, +) / Double(cases.count)
        self.maxRegret = cases.map(\.regret).max() ?? 0
        self.unsafeSelectionCount = cases.filter { $0.rejectedReason != nil }.count
        self.cases = cases
        self.slices = slices
    }
}

public struct PortfolioRouterEvaluator: Sendable {
    public let artifact: PortfolioModelArtifact

    public init(artifact: PortfolioModelArtifact) {
        self.artifact = artifact
    }

    public func evaluate(_ dataset: PortfolioTrainingDataset) -> PortfolioRouterEvaluationReport {
        let rowsByCase = Dictionary(grouping: dataset.rows, by: \.caseID)
        var cases: [PortfolioRouterEvaluationCase] = []

        for caseID in rowsByCase.keys.sorted() {
            guard let rows = rowsByCase[caseID] else { continue }
            let eligibleRows = rows.filter { $0.eligible && !$0.safetyFailure && $0.utility.isFinite }
            guard let oracle = eligibleRows.max(by: { $0.utility < $1.utility }) else { continue }
            let selected = selectRow(from: eligibleRows)
            let chosen = selected ?? eligibleRows.first(where: { $0.arm == .graph }) ?? oracle
            let rejectedReason = selected == nil ? "no eligible learned score" : nil
            cases.append(PortfolioRouterEvaluationCase(
                caseID: caseID,
                selectedArm: chosen.arm,
                oracleArm: oracle.arm,
                selectedUtility: chosen.utility,
                oracleUtility: oracle.utility,
                regret: oracle.utility - chosen.utility,
                rejectedReason: rejectedReason
            ))
        }

        return PortfolioRouterEvaluationReport(
            datasetID: dataset.datasetID,
            modelVersion: artifact.modelVersion,
            cases: cases,
            slices: makeSlices(rowsByCase: rowsByCase, cases: cases)
        )
    }

    public static func write(_ report: PortfolioRouterEvaluationReport, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: url)
    }

    public static func loadArtifact(from url: URL) throws -> PortfolioModelArtifact {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PortfolioModelArtifact.self, from: Data(contentsOf: url))
    }

    private func selectRow(from rows: [PortfolioTrainingRow]) -> PortfolioTrainingRow? {
        var scored: [(row: PortfolioTrainingRow, score: Double)] = []
        for row in rows {
            guard let model = try? artifact.model(for: row.arm) else { continue }
            scored.append((row, model.score(row.features)))
        }
        let ranked = scored.sorted {
            if $0.score == $1.score {
                return armPriority($0.row.arm) < armPriority($1.row.arm)
            }
            return $0.score > $1.score
        }
        guard let best = ranked.first else { return nil }
        if let second = ranked.dropFirst().first,
           best.score - second.score < artifact.minimumUtilityMargin {
            return rows.first { $0.arm == .graph }
        }
        return best.row
    }

    private func makeSlices(
        rowsByCase: [String: [PortfolioTrainingRow]],
        cases: [PortfolioRouterEvaluationCase]
    ) -> [PortfolioRouterSliceSummary] {
        let regretByCase = Dictionary(uniqueKeysWithValues: cases.map { ($0.caseID, $0.regret) })
        var buckets: [String: [Double]] = [:]
        for (caseID, rows) in rowsByCase {
            guard let first = rows.first, let regret = regretByCase[caseID] else { continue }
            buckets["operation:\(first.features.operation.value?.rawValue ?? "unknown")", default: []].append(regret)
            buckets["risk:\(first.features.riskFloor.value.map(String.init(describing:)) ?? "unknown")", default: []].append(regret)
            buckets["language:\(first.features.languageOODSignal.value?.rawValue ?? "unknown")", default: []].append(regret)
            buckets["warm:\(first.features.warmStateHint.value?.rawValue ?? "unknown")", default: []].append(regret)
            if rows.contains(where: \.escalated) {
                buckets["escalation:true", default: []].append(regret)
            } else {
                buckets["escalation:false", default: []].append(regret)
            }
        }
        return buckets.keys.sorted().map { PortfolioRouterSliceSummary(name: $0, regrets: buckets[$0] ?? []) }
    }

    private func armPriority(_ arm: FoundationModelCallArm) -> Int {
        switch arm {
        case .graph: return 0
        case .graphWithTier1: return 1
        case .verifierLoop: return 2
        default: return 99
        }
    }
}
