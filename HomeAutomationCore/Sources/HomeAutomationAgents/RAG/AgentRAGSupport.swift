import Foundation
import HomeAutomationRAG

enum AgentRAGSupport {
    static func nluInput(
        _ input: String,
        task: String,
        contextRetriever: ContextRetriever?
    ) async -> String {
        guard let contextRetriever else { return input }
        let examples = await contextRetriever.retrieve(
            query: input,
            topK: 3,
            filter: MetadataFilter(source: .nlDataset)
        )
        guard !examples.isEmpty else { return input }

        let fewShot = examples
            .map { $0.chunk.content }
            .joined(separator: "\n")

        return """
        Relevant prior smart-home examples for \(task):
        \(fewShot)

        User command:
        \(input)
        """
    }

    static func stableUnique<T>(
        _ values: [T],
        by key: (T) -> String
    ) -> [T] {
        var seen = Set<String>()
        var result: [T] = []
        for value in values {
            let id = key(value)
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            result.append(value)
        }
        return result
    }
}
