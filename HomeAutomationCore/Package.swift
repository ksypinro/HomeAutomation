// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "HomeAutomationCore",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "HomeAutomationCore",
            targets: ["HomeAutomationCore"]
        ),
        .library(
            name: "HomeAutomationRAG",
            targets: ["HomeAutomationRAG"]
        ),
        .library(
            name: "HomeAutomationAgents",
            targets: ["HomeAutomationAgents"]
        ),
        .library(
            name: "HomeAutomationOrchestrator",
            targets: ["HomeAutomationOrchestrator"]
        ),
        .library(
            name: "HomeAutomationEvaluation",
            targets: ["HomeAutomationEvaluation"]
        ),
        .executable(
            name: "home-automation-eval",
            targets: ["HomeAutomationEvalCLI"]
        )
    ],
    targets: [
        .target(
            name: "HomeAutomationCore",
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "HomeAutomationRAG",
            dependencies: ["HomeAutomationCore"]
        ),
        .target(
            name: "HomeAutomationAgents",
            dependencies: [
                "HomeAutomationCore",
                "HomeAutomationRAG"
            ]
        ),
        .target(
            name: "HomeAutomationOrchestrator",
            dependencies: [
                "HomeAutomationCore",
                "HomeAutomationRAG",
                "HomeAutomationAgents"
            ]
        ),
        .target(
            name: "HomeAutomationEvaluation",
            dependencies: [
                "HomeAutomationCore",
                "HomeAutomationRAG",
                "HomeAutomationAgents",
                "HomeAutomationOrchestrator"
            ],
            resources: [
                .copy("Resources/EvaluationDatasets")
            ]
        ),
        .executableTarget(
            name: "HomeAutomationEvalCLI",
            dependencies: [
                "HomeAutomationEvaluation"
            ]
        ),
        .testTarget(
            name: "HomeAutomationRAGTests",
            dependencies: [
                "HomeAutomationCore",
                "HomeAutomationRAG"
            ]
        ),
        .testTarget(
            name: "HomeAutomationAgentTests",
            dependencies: [
                "HomeAutomationAgents",
                "HomeAutomationCore",
                "HomeAutomationRAG"
            ]
        ),
        .testTarget(
            name: "HomeAutomationCoreTests",
            dependencies: [
                "HomeAutomationCore"
            ]
        ),
        .testTarget(
            name: "HomeAutomationOrchestratorTests",
            dependencies: [
                "HomeAutomationAgents",
                "HomeAutomationCore",
                "HomeAutomationOrchestrator"
            ]
        ),
        .testTarget(
            name: "HomeAutomationEvaluationTests",
            dependencies: [
                "HomeAutomationCore",
                "HomeAutomationEvaluation"
            ]
        )
    ]
)
