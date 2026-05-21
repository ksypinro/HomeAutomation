# Implementation Plan - Sophisticated & Modular Multi-Model Architecture

This implementation plan proposes five key architectural advancements to make the `HomeAutomation` Multi-Agent/Multi-Model system significantly more modular, cost-efficient, performant, and sophisticated.

## Executive Summary

The current architecture employs 27 specialist agents, 6 of which run parallel Foundation Model sessions for NLU tasks, plus separate sessions for draft generation, condition resolution, and fallback. While highly robust, the current model invocation is tightly coupled, uses a single default model configuration, and executes full parallel pipelines regardless of command complexity or system resource constraints (battery, network, CPU).

We propose introducing a **Modular Multi-Model Decoupling Layer**, an **Adaptive System-Aware Routing Engine**, **Coarse-to-Fine Pipeline Shifting**, **Adaptive Prompt & Schema Compression**, and **Multi-Model Cost/Performance Telemetry**.

---

## Proposed Changes

### Component 1: Unified Model Registry and Client Decoupling (`HomeAutomationCore`)

#### [NEW] [HomeModelRegistry.swift](file:///Users/samin/Downloads/untitled%20folder/HomeAutomation/HomeAutomationCore/Sources/HomeAutomationCore/HomeAutomation/HomeModelRegistry.swift)
Decompose direct `LanguageModelSession` instantiation by introducing an abstract model provider. This allows agents to request a model session based on required **capabilities** and **tiers**, rather than hardcoding the defaults.

- **Model Tiers**:
  - `.lightweight` (fast local classification: language detection, domain, intent)
  - `.standard` (balanced: slot extraction, risk classification, ranking)
  - `.advanced` (complex reasoning & tool-use: draft generation, repair)
- **Features**:
  - Support for dynamic model-to-tier binding.
  - Multi-provider adapters (local Apple System model, cloud-based fallback models, or custom fine-tuned LoRA adapters).
  - Centralized model prewarming, caching, and thread-safe session reuse.

```swift
public enum HomeModelTier: String, Sendable, Codable {
    case lightweight
    case standard
    case advanced
}

public protocol HomeModelManaging: Sendable {
    func isModelAvailable(for tier: HomeModelTier) -> Bool
    func session(for tier: HomeModelTier, instructions: String, tools: [any Tool]) throws -> LanguageModelSession
    func prewarm(tier: HomeModelTier)
}
```

---

### Component 2: Adaptive, System-Aware Routing Policy (`HomeAutomationOrchestrator`)

#### [NEW] [HomeAdaptiveRoutingEngine.swift](file:///Users/samin/Downloads/untitled%20folder/HomeAutomation/HomeAutomationCore/Sources/HomeAutomationOrchestrator/HomeAdaptiveRoutingEngine.swift)
Introduce a sophisticated policy coordinator that assesses device hardware and environmental metrics before fanning out multi-model agent execution.

- **System Context Factors**:
  - **Battery Level & State**: Switch to purely deterministic pathways or compress models to `.lightweight` tier if battery is low (< 20%) and not charging.
  - **Thermal State**: Prevent high concurrency (parallel NLU runs) if the processor is thermally throttled.
  - **Network Quality**: Fallback to local deterministic rules if network latency is high or disconnected.
  - **Token Budgets & Cost Constraints**: Cap the maximum allowed standard/advanced tokens per session.

```swift
public struct SystemPerformanceMetrics: Sendable {
    public let batteryLevel: Float
    public let isCharging: Bool
    public let thermalState: ProcessInfo.ThermalState
    public let isConnectedToHighSpeedNetwork: Bool
}

public final class HomeAdaptiveRoutingEngine: Sendable {
    public func resolveModelTier(for task: AgentID, systemMetrics: SystemPerformanceMetrics) -> HomeModelTier {
        // Fallback cascades based on device pressure
    }
}
```

---

### Component 3: Coarse-to-Fine Pipeline Shifting (Asymmetric Router)

#### [MODIFY] [GraphPlanner.swift](file:///Users/samin/Downloads/untitled%20folder/HomeAutomation/HomeAutomationCore/Sources/HomeAutomationOrchestrator/GraphPlanner.swift)
Currently, every command goes through the full 6-agent NLU pipeline. We propose adding an **Asymmetric Pipeline Router** at the beginning of the `root-command-graph`.

- **Asymmetric Router Node**:
  - Uses a lightweight regex classifier or high-speed model call.
  - If a command is high-confidence, standard, and non-ambiguous (e.g., "Turn on bedroom light"), it bypasses NLU extraction completely, directly resolving the device and command using a cached direct mapping.
  - If a command is complex, relative, or contains ambiguous slots, the router branches the scheduler into the full parallel NLU and RAG graph.
  - This reduces average latency by **60–80%** for common happy-path inputs.

---

### Component 4: Adaptive Prompt & Schema Compression (`HomeAutomationCore`)

#### [MODIFY] [FoundationModelContextBudgeter.swift](file:///Users/samin/Downloads/untitled%20folder/HomeAutomation/HomeAutomationCore/Sources/HomeAutomationCore/HomeAutomation/FoundationModelContextBudgeter.swift)
Enhance the existing budgeter to support structural priority-based prompt pruning when smart home registries scale up.

- **Priority-Based Compactor**:
  1. **Priority 1 (Critical)**: Core Instructions & Final Selected Device.
  2. **Priority 2 (High)**: Canonical Capability Definition for the target.
  3. **Priority 3 (Medium)**: Highly scored RAG snippets.
  4. **Priority 4 (Low)**: Few-shot examples & older conversation turns.
- **Dynamic Compaction**:
  - Instead of hard truncation, automatically strips low-priority blocks and reduces candidate schema descriptions (e.g., dropping attribute descriptions, keeping only raw command signatures) to fit the target model's sliding token budget.

---

### Component 5: Cost, Telemetry, and Performance Dashboard (`HomeAutomationApp`)

#### [MODIFY] [HomeAutomationViewModel.swift](file:///Users/samin/Downloads/untitled%20folder/HomeAutomation/HomeAutomationApp/HomeAutomationViewModel.swift)
#### [MODIFY] [HomeAutomationView.swift](file:///Users/samin/Downloads/untitled%20folder/HomeAutomation/HomeAutomationApp/HomeAutomationView.swift)
Expose model-specific efficiency telemetry in the SwiftUI App Dashboard:
- Visual timeline displaying which model tier (`lightweight`, `standard`, `advanced`) was called for each agent.
- Token usage counters (input, output, and remaining context budget).
- Cost calculator simulating API costs for both local on-device and simulated cloud executions.
- Active system state badges (Battery Throttling, Thermal Warning, High Network Latency) showing how the routing engine adapted.

---

## Verification Plan

### Automated Tests
1. **Model Registry Decoupling Test**: Verify that NLU/Draft agents correctly receive decoupled model sessions from the registry and that swap-outs work.
2. **Adaptive Throttling Test**: Mock low battery and high thermal states to verify that parallel agent calls are skipped or redirected to lightweight local equivalents.
3. **Asymmetric Routing Test**: Verify that happy path commands complete without invoking the 6-agent NLU fan-out, while complex commands trigger full resolution.
4. **Budget Compaction Test**: Test the context budgeter with a simulated registry of 100+ devices, ensuring prompt sizes are compressed without causing token overflow.

### Manual Verification
- Deploy and run the app in the simulator with simulated system state changes (Throttling, low battery) and verify the pipeline dashboard visualizes the changes in real-time.
