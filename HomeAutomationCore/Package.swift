// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HomeAutomationCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
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
            name: "HomeAutomationResolver",
            targets: ["HomeAutomationResolver"]
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
            name: "HomeAutomationResolver",
            dependencies: ["HomeAutomationCore"]
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
            name: "HomeAutomationOrchestratorTests",
            dependencies: [
                "HomeAutomationAgents",
                "HomeAutomationCore",
                "HomeAutomationOrchestrator",
                "HomeAutomationResolver"
            ]
        ),
        .testTarget(
            name: "HomeAutomationResolverTests",
            dependencies: [
                "HomeAutomationCore",
                "HomeAutomationResolver"
            ]
        )
    ]
)
