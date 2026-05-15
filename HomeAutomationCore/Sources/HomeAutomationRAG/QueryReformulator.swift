import Foundation

public enum QueryReformulator {
    public static func reformulate(rawText: String, hints: NLURetrievalHints?) -> String {
        reformulate(
            rawText: rawText,
            hints: hints,
            automationConcepts: [],
            conditionOperators: [],
            repeatHints: []
        )
    }

    public static func reformulate(_ query: StructuredRetrievalQuery) -> StructuredRetrievalQuery {
        StructuredRetrievalQuery(
            rawText: query.rawText,
            semanticText: reformulate(
                rawText: query.semanticText,
                hints: query.nluHints,
                automationConcepts: query.automationConcepts,
                conditionOperators: query.conditionOperators,
                repeatHints: query.repeatHints
            ),
            keywordTerms: query.keywordTerms,
            metadataFilter: query.metadataFilter,
            nluHints: query.nluHints,
            operation: query.operation,
            automationConcepts: query.automationConcepts,
            conditionOperators: query.conditionOperators,
            repeatHints: query.repeatHints,
            strategy: query.strategy,
            minScore: query.minScore,
            topK: query.topK
        )
    }

    public static func reformulate(
        rawText: String,
        hints: NLURetrievalHints?,
        automationConcepts: [String],
        conditionOperators: [String],
        repeatHints: [String]
    ) -> String {
        guard let hints, !hints.isEmpty else {
            let automationExpansions = [
                automationConcepts.joined(separator: " "),
                conditionOperators.joined(separator: " "),
                repeatHints.joined(separator: " ")
            ]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return automationExpansions.isEmpty
                ? rawText
                : ([rawText] + automationExpansions).joined(separator: " ")
        }

        let expansions = [
            hints.intentFamilies.joined(separator: " "),
            hints.deviceTypes.joined(separator: " "),
            hints.rooms.joined(separator: " "),
            hints.capabilities.joined(separator: " "),
            automationConcepts.joined(separator: " "),
            conditionOperators.joined(separator: " "),
            repeatHints.joined(separator: " ")
        ]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !expansions.isEmpty else { return rawText }
        return ([rawText] + expansions).joined(separator: " ")
    }
}
