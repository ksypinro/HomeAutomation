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
                "HomeAutomationOrchestrator"
            ]
        )
    ]
)
