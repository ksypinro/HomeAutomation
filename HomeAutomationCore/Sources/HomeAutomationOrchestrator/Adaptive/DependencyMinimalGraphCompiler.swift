import Foundation
import HomeAutomationAgents
import HomeAutomationCore

public enum GraphCompilationMode: String, Sendable, Hashable, Codable {
    case disabled
    case shadow
    case active

    public var computesCompiledGraph: Bool {
        self == .shadow || self == .active
    }
}

public enum GraphCompilationFallbackReason: String, Sendable, Hashable, Codable {
    case none
    case modeDisabled
    case invalidSeed
    case missingManifest
    case unsafePruningAttempt
    case validationFailed
    case compilerError
}

public struct GraphCompilationSeed: Sendable, Hashable {
    public let availableKeys: Set<String>
    public let availableArtifacts: [String: ContextArtifactDescriptor]
    public let isTrustedFresh: Bool
    public let diagnostics: [String]

    public init(
        availableKeys: Set<String>,
        availableArtifacts: [String: ContextArtifactDescriptor] = [:],
        isTrustedFresh: Bool = true,
        diagnostics: [String] = []
    ) {
        self.availableKeys = availableKeys
        self.availableArtifacts = availableArtifacts
        self.isTrustedFresh = isTrustedFresh
        self.diagnostics = diagnostics
    }

    public static func from(context: ResolutionContext) -> GraphCompilationSeed {
        GraphCompilationSeed(
            availableKeys: Self.availableKeys(in: context),
            availableArtifacts: Self.availableArtifacts(in: context),
            isTrustedFresh: true
        )
    }

    public static func from(
        prepared: PreparedOrchestrationRequest,
        currentSnapshot: PreparedDeviceSnapshot?
    ) -> GraphCompilationSeed {
        var keys: Set<String> = [
            "request.text",
            "request.executeLowRiskCommands",
            "request.automationCreationOptions",
            ResolutionContextPatchKey.resolutionState.rawValue
        ]
        if prepared.featureSnapshot.operation.value != nil {
            keys.insert(ResolutionContextPatchKey.operation.rawValue)
        }
        if prepared.featureSnapshot.languageOODSignal.value != nil {
            keys.insert(ResolutionContextPatchKey.language.rawValue)
            keys.insert(ResolutionContextPatchKey.domain.rawValue)
        }
        if prepared.featureSnapshot.riskFloor.value != nil {
            keys.insert(ResolutionContextPatchKey.risk.rawValue)
        }
        let freshness = prepared.registryFreshness(comparedTo: currentSnapshot)
        let trusted = prepared.diagnostics.isEmpty &&
            freshness == .fresh &&
            prepared.featureSnapshot.languageOODSignal.value == .inDomain
        return GraphCompilationSeed(
            availableKeys: keys,
            isTrustedFresh: trusted,
            diagnostics: prepared.diagnostics.map(\.detail)
        )
    }

    public func containsArtifact(_ descriptor: ContextArtifactDescriptor) -> Bool {
        availableArtifacts[descriptor.storageKey]?.valueTypeName == descriptor.valueTypeName
    }

    private static func availableKeys(in context: ResolutionContext) -> Set<String> {
        var keys: Set<String> = [
            "request.text",
            "request.executeLowRiskCommands",
            "request.automationCreationOptions"
        ]
        if context.operation != nil { keys.insert(ResolutionContextPatchKey.operation.rawValue) }
        if context.language != nil { keys.insert(ResolutionContextPatchKey.language.rawValue) }
        if context.domain != nil { keys.insert(ResolutionContextPatchKey.domain.rawValue) }
        if context.intent != nil { keys.insert(ResolutionContextPatchKey.intent.rawValue) }
        if context.deviceType != nil { keys.insert(ResolutionContextPatchKey.deviceType.rawValue) }
        if context.slots != nil { keys.insert(ResolutionContextPatchKey.slots.rawValue) }
        if context.risk != nil { keys.insert(ResolutionContextPatchKey.risk.rawValue) }
        if context.resolutionState != nil { keys.insert(ResolutionContextPatchKey.resolutionState.rawValue) }
        if !context.retrievedCandidates.isEmpty { keys.insert(ResolutionContextPatchKey.retrievedCandidates.rawValue) }
        if !context.selectedCandidateIDs.isEmpty { keys.insert(ResolutionContextPatchKey.selectedCandidateIDs.rawValue) }
        if context.aggregation != nil { keys.insert(ResolutionContextPatchKey.aggregation.rawValue) }
        if !context.hydratedCandidates.isEmpty { keys.insert(ResolutionContextPatchKey.hydratedCandidates.rawValue) }
        if context.capabilityDecision != nil { keys.insert(ResolutionContextPatchKey.capabilityDecision.rawValue) }
        if !context.knowledgeSnippets.isEmpty { keys.insert(ResolutionContextPatchKey.knowledgeSnippets.rawValue) }
        if !context.retrievalReports.isEmpty { keys.insert(ResolutionContextPatchKey.retrievalReports.rawValue) }
        if context.instructionPackage != nil { keys.insert(ResolutionContextPatchKey.instructionPackage.rawValue) }
        if context.draft != nil { keys.insert(ResolutionContextPatchKey.draft.rawValue) }
        if context.executionPlan != nil { keys.insert(ResolutionContextPatchKey.executionPlan.rawValue) }
        if context.resolution != nil { keys.insert(ResolutionContextPatchKey.resolution.rawValue) }
        for values in context.scopedValues.values {
            keys.formUnion(values.keys)
        }
        return keys
    }

    private static func availableArtifacts(in context: ResolutionContext) -> [String: ContextArtifactDescriptor] {
        var descriptors: [String: ContextArtifactDescriptor] = [:]
        for (scope, values) in context.scopedValues {
            for (name, value) in values {
                let descriptor = ContextArtifactDescriptor(
                    name: name,
                    scope: scope,
                    valueTypeName: value.typeName
                )
                descriptors[descriptor.storageKey] = descriptor
            }
        }
        return descriptors
    }
}

public struct GraphCompilationReport: Sendable, Hashable, Codable {
    public let mode: GraphCompilationMode
    public let templateID: GraphTemplateID
    public let templateVersion: Int
    public let executedGraphID: String
    public let compiledGraphID: String?
    public let didCompile: Bool
    public let didExecuteCompiledGraph: Bool
    public let fallbackReason: GraphCompilationFallbackReason
    public let prunedNodeIDs: [String]
    public let retainedNodeIDs: [String]
    public let seedKeys: [String]
    public let validationErrors: [String]

    public init(
        mode: GraphCompilationMode,
        templateID: GraphTemplateID,
        templateVersion: Int,
        executedGraphID: String,
        compiledGraphID: String? = nil,
        didCompile: Bool,
        didExecuteCompiledGraph: Bool,
        fallbackReason: GraphCompilationFallbackReason,
        prunedNodeIDs: [String] = [],
        retainedNodeIDs: [String] = [],
        seedKeys: [String] = [],
        validationErrors: [String] = []
    ) {
        self.mode = mode
        self.templateID = templateID
        self.templateVersion = templateVersion
        self.executedGraphID = executedGraphID
        self.compiledGraphID = compiledGraphID
        self.didCompile = didCompile
        self.didExecuteCompiledGraph = didExecuteCompiledGraph
        self.fallbackReason = fallbackReason
        self.prunedNodeIDs = prunedNodeIDs
        self.retainedNodeIDs = retainedNodeIDs
        self.seedKeys = seedKeys
        self.validationErrors = validationErrors
    }

    public static func staticTemplate(template: GraphTemplate) -> GraphCompilationReport {
        GraphCompilationReport(
            mode: .disabled,
            templateID: template.templateID,
            templateVersion: template.version.value,
            executedGraphID: template.graph.id,
            didCompile: false,
            didExecuteCompiledGraph: false,
            fallbackReason: .modeDisabled,
            retainedNodeIDs: template.graph.nodes.map(\.id).sorted()
        )
    }
}

public struct DependencyMinimalGraphCompiler: Sendable {
    public init() {}

    public func makePlan(
        template: GraphTemplate,
        registry: AgentRegistry,
        seed: GraphCompilationSeed,
        mode: GraphCompilationMode,
        initialContext: ResolutionContext? = nil
    ) -> GraphExecutionPlan {
        guard mode.computesCompiledGraph else {
            return template.staticPlan()
        }
        guard seed.isTrustedFresh else {
            return fallbackPlan(
                template: template,
                mode: mode,
                reason: .invalidSeed,
                seed: seed,
                validationErrors: seed.diagnostics
            )
        }

        let compileResult = compile(template: template, registry: registry, seed: seed)
        switch compileResult {
        case .failure(let reason, let errors):
            return fallbackPlan(
                template: template,
                mode: mode,
                reason: reason,
                seed: seed,
                validationErrors: errors
            )
        case .success(let compiledGraph, let prunedNodeIDs):
            let validationErrors = GraphValidator().validate(
                compiledGraph,
                registry: registry,
                initialContext: initialContext
            )
            guard validationErrors.isEmpty else {
                return fallbackPlan(
                    template: template,
                    mode: mode,
                    reason: .validationFailed,
                    seed: seed,
                    compiledGraphID: compiledGraph.id,
                    prunedNodeIDs: prunedNodeIDs,
                    validationErrors: validationErrors.map(\.description)
                )
            }

            let executedGraph = mode == .active ? compiledGraph : template.graph
            return GraphExecutionPlan(
                graph: executedGraph,
                isFallbackOnly: false,
                compilationReport: GraphCompilationReport(
                    mode: mode,
                    templateID: template.templateID,
                    templateVersion: template.version.value,
                    executedGraphID: executedGraph.id,
                    compiledGraphID: compiledGraph.id,
                    didCompile: true,
                    didExecuteCompiledGraph: mode == .active,
                    fallbackReason: .none,
                    prunedNodeIDs: prunedNodeIDs.sorted(),
                    retainedNodeIDs: compiledGraph.nodes.map(\.id).sorted(),
                    seedKeys: seed.availableKeys.sorted()
                ),
                criticalPath: CriticalPathAnalyzer().analyze(executedGraph)
            )
        }
    }

    private enum CompileResult {
        case success(OrchestrationGraph, prunedNodeIDs: [String])
        case failure(GraphCompilationFallbackReason, errors: [String])
    }

    private func compile(
        template: GraphTemplate,
        registry: AgentRegistry,
        seed: GraphCompilationSeed
    ) -> CompileResult {
        let manifests = selectedManifestsByNode(template.graph, registry: registry)
        let missingManifestNodeIDs = template.graph.nodes
            .filter { manifests[$0.id] == nil }
            .map(\.id)
        guard missingManifestNodeIDs.isEmpty else {
            return .failure(.missingManifest, errors: missingManifestNodeIDs)
        }

        let prunableNodeIDs = template.graph.nodes.compactMap { node -> String? in
            guard !isNonPrunable(node: node, template: template, manifest: manifests[node.id]) else {
                return nil
            }
            guard let manifest = manifests[node.id],
                  producesSatisfied(manifest: manifest, seed: seed) else {
                return nil
            }
            return node.id
        }
        let prunedSet = Set(prunableNodeIDs)
        let retainedNodes = template.graph.nodes.filter { !prunedSet.contains($0.id) }
        guard !retainedNodes.isEmpty else {
            return .failure(.unsafePruningAttempt, errors: ["Compiler attempted to prune every node."])
        }

        let retainedIDs = Set(retainedNodes.map(\.id))
        let edges = reconstructedEdges(
            template: template,
            retainedNodes: retainedNodes,
            retainedIDs: retainedIDs,
            manifests: manifests,
            seed: seed
        )
        let entryNodeIDs = inferredEntryNodeIDs(nodes: retainedNodes, edges: edges)
        let compiled = OrchestrationGraph(
            id: "\(template.graph.id)-compiled-v\(template.version.value)",
            goal: template.graph.goal,
            nodes: retainedNodes,
            edges: edges,
            entryNodeIDs: entryNodeIDs
        )
        return .success(compiled, prunedNodeIDs: prunableNodeIDs)
    }

    private func fallbackPlan(
        template: GraphTemplate,
        mode: GraphCompilationMode,
        reason: GraphCompilationFallbackReason,
        seed: GraphCompilationSeed,
        compiledGraphID: String? = nil,
        prunedNodeIDs: [String] = [],
        validationErrors: [String] = []
    ) -> GraphExecutionPlan {
        GraphExecutionPlan(
            graph: template.graph,
            isFallbackOnly: false,
            compilationReport: GraphCompilationReport(
                mode: mode,
                templateID: template.templateID,
                templateVersion: template.version.value,
                executedGraphID: template.graph.id,
                compiledGraphID: compiledGraphID,
                didCompile: compiledGraphID != nil,
                didExecuteCompiledGraph: false,
                fallbackReason: reason,
                prunedNodeIDs: prunedNodeIDs.sorted(),
                retainedNodeIDs: template.graph.nodes.map(\.id).sorted(),
                seedKeys: seed.availableKeys.sorted(),
                validationErrors: validationErrors
            ),
            criticalPath: CriticalPathAnalyzer().analyze(template.graph)
        )
    }

    private func selectedManifestsByNode(
        _ graph: OrchestrationGraph,
        registry: AgentRegistry
    ) -> [String: AgentManifest] {
        graph.nodes.reduce(into: [:]) { partial, node in
            switch node.requirement {
            case .byID(let id):
                partial[node.id] = registry.manifest(for: id)
            case .byCapability(let capability):
                partial[node.id] = registry.agents(for: capability, operation: graph.goal.operationKind).first?.manifest ??
                    registry.agents(for: capability).first?.manifest
            }
        }
    }

    private func isNonPrunable(
        node: GraphNode,
        template: GraphTemplate,
        manifest: AgentManifest?
    ) -> Bool {
        template.mandatoryNodeIDs.contains(node.id) ||
            node.executionPolicy == .safetyGate ||
            node.interrupt != nil ||
            manifest?.safetyRole == .requiredGate ||
            manifest?.safetyRole == .executionGate
    }

    private func producesSatisfied(manifest: AgentManifest, seed: GraphCompilationSeed) -> Bool {
        guard !manifest.produces.isEmpty || !manifest.producedArtifacts.isEmpty else {
            return false
        }
        let keysSatisfied = manifest.produces.allSatisfy { seed.availableKeys.contains($0) }
        let artifactsSatisfied = manifest.producedArtifacts.allSatisfy { contract in
            contract.requirement == .optional || seed.containsArtifact(contract.descriptor)
        }
        return keysSatisfied && artifactsSatisfied
    }

    private func reconstructedEdges(
        template: GraphTemplate,
        retainedNodes: [GraphNode],
        retainedIDs: Set<String>,
        manifests: [String: AgentManifest],
        seed: GraphCompilationSeed
    ) -> [GraphEdge] {
        var edges = Set<GraphEdge>()
        for edge in template.intentionalEdges where retainedIDs.contains(edge.from) && retainedIDs.contains(edge.to) {
            edges.insert(edge)
        }
        for edge in template.graph.edges where retainedIDs.contains(edge.from) && retainedIDs.contains(edge.to) {
            let fromManifest = manifests[edge.from]
            let toManifest = manifests[edge.to]
            if hasDataDependency(from: fromManifest, to: toManifest) ||
                template.intentionalEdges.contains(edge) {
                edges.insert(edge)
            }
        }
        for consumer in retainedNodes {
            guard let consumerManifest = manifests[consumer.id] else { continue }
            for producer in retainedNodes where producer.id != consumer.id {
                guard let producerManifest = manifests[producer.id] else { continue }
                if hasDataDependency(from: producerManifest, to: consumerManifest) {
                    edges.insert(GraphEdge(from: producer.id, to: consumer.id))
                }
            }
            let missingRequiredKeys = consumerManifest.consumes.filter { !seed.availableKeys.contains($0) }
            let hasProviderForEveryMissingKey = missingRequiredKeys.allSatisfy { key in
                retainedNodes.contains { producer in
                    manifests[producer.id]?.produces.contains(key) == true
                }
            }
            if !hasProviderForEveryMissingKey {
                for edge in template.graph.edges where edge.to == consumer.id && retainedIDs.contains(edge.from) {
                    edges.insert(edge)
                }
            }
        }
        return edges.sorted { lhs, rhs in
            if lhs.from == rhs.from { return lhs.to < rhs.to }
            return lhs.from < rhs.from
        }
    }

    private func hasDataDependency(from producer: AgentManifest?, to consumer: AgentManifest?) -> Bool {
        guard let producer, let consumer else { return false }
        if !producer.produces.intersection(consumer.consumes).isEmpty {
            return true
        }
        let producedArtifacts = Set(producer.producedArtifacts.map(\.descriptor.storageKey))
        let consumedArtifacts = Set(consumer.consumedArtifacts.map(\.descriptor.storageKey))
        return !producedArtifacts.intersection(consumedArtifacts).isEmpty
    }

    private func inferredEntryNodeIDs(nodes: [GraphNode], edges: [GraphEdge]) -> Set<String> {
        let nodeIDs = Set(nodes.map(\.id))
        let incoming = Set(edges.map(\.to))
        let entries = nodeIDs.subtracting(incoming)
        return entries.isEmpty ? nodeIDs : entries
    }
}

private extension OrchestrationGoal {
    var operationKind: HomeAutomationOperationKind {
        switch self {
        case .rootRouting:
            return .executeDeviceCommand
        case .executeDeviceCommand:
            return .executeDeviceCommand
        case .automationCreation:
            return .automationCreation
        case .unsupported:
            return .unsupported
        }
    }
}
