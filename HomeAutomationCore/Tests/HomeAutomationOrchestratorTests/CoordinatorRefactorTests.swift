import Foundation
import HomeAutomationCore
import HomeAutomationOrchestrator
import Testing

@Suite
struct CoordinatorRefactorTests {
    @Test
    func coordinatorTypeInventoryListsEverySourceDeclaration() throws {
        let paths = try ProjectPaths.fromTestFile(#filePath)
        let inventory = try String(
            contentsOf: paths.workspaceRoot.appendingPathComponent("Docs/CoordinatorTypeInventory.md"),
            encoding: .utf8
        )
        let declarations = try Self.sourceDeclarations(in: paths.sourcesRoot)

        for declaration in declarations {
            #expect(
                inventory.contains("`\(declaration.name)`"),
                "Missing \(declaration.kind) \(declaration.name) from coordinator inventory"
            )
        }
    }

    @Test
    func productionDependencyConstructionIsCoordinatorBounded() throws {
        let paths = try ProjectPaths.fromTestFile(#filePath)
        let guardedPatterns = [
            "MockHomeDeviceRegistry(",
            "AgentCommandValidator(",
            "AgentBixbyFallbackMapper(",
            "AgentDraftResolver(",
            "HomeCandidateResolverSupport(",
            "AgentToolProvider(",
            "AgentInstructionSetFactory(",
            "AgentPlanExecutor("
        ]
        let allowedFiles = [
            "HomeAutomationCore/Sources/HomeAutomationOrchestrator/HomeAutomationCoordinator.swift"
        ]
        let violations = try Self.sourceLines(in: paths.sourcesRoot).filter { line in
            guardedPatterns.contains { line.text.contains($0) } &&
                !allowedFiles.contains { line.relativePath == $0 }
        }

        #expect(
            violations.isEmpty,
            "Dependency construction escaped coordinator ownership: \(violations.map(\.description).joined(separator: "; "))"
        )
    }

    @Test
    func coordinatorPropagatesProvidedDeviceRegistry() throws {
        let registry = MockHomeDeviceRegistry()
        let coordinator = HomeAutomationRootCoordinator(
            deviceRegistry: registry,
            foundationModelAvailability: { false }
        )
        let propagated = try #require(coordinator.deviceCoordinator.deviceRegistry as? MockHomeDeviceRegistry)

        #expect(propagated === registry)
    }

    private struct ProjectPaths {
        let workspaceRoot: URL
        let sourcesRoot: URL

        static func fromTestFile(_ filePath: String) throws -> ProjectPaths {
            let testFile = URL(fileURLWithPath: filePath)
            let packageRoot = testFile
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let workspaceRoot = packageRoot.deletingLastPathComponent()
            return ProjectPaths(
                workspaceRoot: workspaceRoot,
                sourcesRoot: packageRoot.appendingPathComponent("Sources", isDirectory: true)
            )
        }
    }

    private struct SourceDeclaration {
        let kind: String
        let name: String
    }

    private struct SourceLine: CustomStringConvertible {
        let relativePath: String
        let lineNumber: Int
        let text: String

        var description: String {
            "\(relativePath):\(lineNumber): \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }

    private static func sourceDeclarations(in root: URL) throws -> [SourceDeclaration] {
        let pattern = #"^\s*(?:public|internal|private|fileprivate)?\s*(?:final\s+)?(class|struct|actor)\s+([A-Za-z_][A-Za-z0-9_]*)\b"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        return try swiftSourceFiles(in: root).flatMap { file in
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.matches(in: text, range: range).compactMap { match -> SourceDeclaration? in
                guard
                    let kindRange = Range(match.range(at: 1), in: text),
                    let nameRange = Range(match.range(at: 2), in: text)
                else {
                    return nil
                }
                return SourceDeclaration(
                    kind: String(text[kindRange]),
                    name: String(text[nameRange])
                )
            }
        }
    }

    private static func sourceLines(in root: URL) throws -> [SourceLine] {
        let workspaceRoot = root
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try swiftSourceFiles(in: root).flatMap { file in
            let relativePath = file.path.replacingOccurrences(
                of: workspaceRoot.path + "/",
                with: ""
            )
            return try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
                .map { index, line in
                    SourceLine(
                        relativePath: relativePath,
                        lineNumber: index + 1,
                        text: String(line)
                    )
                }
        }
    }

    private static func swiftSourceFiles(in root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == "swift" else {
                return nil
            }
            return url
        }
    }
}
