import Foundation

public enum DatasetJSONL {
    public static func read<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> [T] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { line in
                let data = Data(line.utf8)
                return try decoder.decode(type, from: data)
            }
    }

    public static func write<T: Encodable>(
        _ values: [T],
        to url: URL,
        encoder: JSONEncoder = DatasetJSONL.defaultEncoder()
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let lines = try values.map { value -> String in
            let data = try encoder.encode(value)
            return String(data: data, encoding: .utf8) ?? "{}"
        }
        let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    public static func defaultEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

public struct EvaluationDatasetResourceLoader: Sendable {
    public init() {}

    public func loadBuiltInDataset(named datasetName: String) throws -> GeneratedEvaluationDataset {
        let manifest = try loadBuiltInManifest(named: datasetName)
        let directory = try resourceDirectory(datasetName: datasetName)
        return try loadDataset(manifest: manifest, from: directory)
    }

    public func loadBuiltInManifest(named datasetName: String) throws -> EvaluationDatasetManifest {
        let url = try resourceURL(named: "manifest", fileExtension: "json", datasetName: datasetName)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(EvaluationDatasetManifest.self, from: data)
    }

    public func loadExternalManifest(from datasetDirectory: URL) throws -> EvaluationDatasetManifest {
        let url = datasetDirectory.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(EvaluationDatasetManifest.self, from: data)
    }

    public func loadExternalDataset(from datasetDirectory: URL) throws -> GeneratedEvaluationDataset {
        let manifest = try loadExternalManifest(from: datasetDirectory)
        return try loadDataset(manifest: manifest, from: datasetDirectory)
    }

    private func loadDataset(
        manifest: EvaluationDatasetManifest,
        from datasetDirectory: URL
    ) throws -> GeneratedEvaluationDataset {
        return GeneratedEvaluationDataset(
            manifest: manifest,
            fixtures: try DatasetJSONL.read(
                GeneratedEvaluationFixture.self,
                from: datasetDirectory.appendingPathComponent("fixtures.jsonl")
            ),
            cases: try DatasetJSONL.read(
                GeneratedEvaluationCase.self,
                from: datasetDirectory.appendingPathComponent("cases.jsonl")
            ),
            traceContracts: try DatasetJSONL.read(
                ExpectedTraceContract.self,
                from: datasetDirectory.appendingPathComponent("expected-traces.jsonl")
            ),
            metricsContracts: try DatasetJSONL.read(
                ExpectedMetricsContract.self,
                from: datasetDirectory.appendingPathComponent("expected-metrics.jsonl")
            )
        )
    }

    private func resourceDirectory(datasetName: String) throws -> URL {
        guard let url = Bundle.module.url(
            forResource: datasetName,
            withExtension: nil,
            subdirectory: "EvaluationDatasets"
        ) else {
            throw EvaluationDatasetResourceError.missingResource("EvaluationDatasets/\(datasetName)")
        }
        return url
    }

    private func resourceURL(
        named name: String,
        fileExtension: String,
        datasetName: String
    ) throws -> URL {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "EvaluationDatasets/\(datasetName)"
        ) else {
            throw EvaluationDatasetResourceError.missingResource(
                "EvaluationDatasets/\(datasetName)/\(name).\(fileExtension)"
            )
        }
        return url
    }
}

public struct EvaluationDatasetWriter: Sendable {
    public init() {}

    public func write(_ dataset: GeneratedEvaluationDataset, to directoryURL: URL) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(dataset.manifest)
        try manifestData.write(to: directoryURL.appendingPathComponent("manifest.json"))

        try DatasetJSONL.write(dataset.fixtures, to: directoryURL.appendingPathComponent("fixtures.jsonl"))
        try DatasetJSONL.write(dataset.cases, to: directoryURL.appendingPathComponent("cases.jsonl"))
        try DatasetJSONL.write(dataset.traceContracts, to: directoryURL.appendingPathComponent("expected-traces.jsonl"))
        try DatasetJSONL.write(dataset.metricsContracts, to: directoryURL.appendingPathComponent("expected-metrics.jsonl"))
        try validationReport(for: dataset).write(
            to: directoryURL.appendingPathComponent("dataset-validation-report.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func validationReport(for dataset: GeneratedEvaluationDataset) -> String {
        let validator = DatasetValidator()
        let fixtureIssues = validator.validate(fixtures: dataset.fixtures)
        let caseIssues = validator.validate(cases: dataset.cases, fixtures: dataset.fixtures)
        let issues = fixtureIssues + caseIssues
        var lines = [
            "# Dataset Validation Report",
            "",
            "- Dataset: \(dataset.manifest.name)",
            "- Fixtures: \(dataset.fixtures.count)",
            "- Cases: \(dataset.cases.count)",
            "- Trace contracts: \(dataset.traceContracts.count)",
            "- Metrics contracts: \(dataset.metricsContracts.count)",
            "- Status: \(issues.contains { $0.severity == "error" } ? "failed" : "passed")",
            ""
        ]
        if issues.isEmpty {
            lines.append("No validation issues.")
        } else {
            lines.append("## Issues")
            for issue in issues {
                let scope = [issue.fixtureID, issue.caseID].compactMap { $0 }.joined(separator: " / ")
                lines.append("- [\(issue.severity)] \(scope.isEmpty ? issue.field : "\(scope) \(issue.field)"): \(issue.message)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

public enum EvaluationDatasetResourceError: Error, Sendable, LocalizedError, Equatable {
    case missingResource(String)

    public var errorDescription: String? {
        switch self {
        case .missingResource(let path):
            return "Missing evaluation dataset resource: \(path)"
        }
    }
}
