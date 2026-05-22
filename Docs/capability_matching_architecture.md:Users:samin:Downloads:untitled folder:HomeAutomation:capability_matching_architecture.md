# Capability Matching Architecture

This document explains how the project determines which smart-home capability the user is asking for, for both direct commands and automation action resolution.

Capability matching is not owned by a single class. It is a layered pipeline:

1. NLU detects broad intent and device-type hints.
2. Candidate retrieval/ranking finds the target device or routine.
3. Capability knowledge retrieval adds canonical capability facts.
4. Draft generation chooses the exact `capability` and `command`.
5. Deterministic validation verifies the chosen capability is supported by the selected device.

The final capability is accepted only if it survives validation against the hydrated candidate record and canonical capability registry.

## Source Files

| Area | Files |
| --- | --- |
| Canonical capability catalog | `HomeAutomationCore/Sources/HomeAutomationCore/HomeAutomation/HomeCapabilityRegistry.swift` |
| Intent-to-capability hints | `HomeAutomationCore/Sources/HomeAutomationCore/HomeAutomation/IntentCapabilityMap.swift` |
| Device candidate schema | `HomeAutomationCore/Sources/HomeAutomationCore/HomeAutomation/HomeAutomationModels.swift` |
| Mock registry candidate retrieval | `HomeAutomationCore/Sources/HomeAutomationCore/HomeAutomation/MockHomeDeviceRegistry.swift` |
| Capability RAG agent | `HomeAutomationCore/Sources/HomeAutomationAgents/Knowledge/Capability/CapabilityKnowledgeAgent.swift` |
| Candidate retrieval/ranking/hydration | `HomeAutomationCore/Sources/HomeAutomationAgents/Candidates/...` |
| Prompt/tool package builder | `HomeAutomationCore/Sources/HomeAutomationAgents/Draft/InstructionComposer/AgentInstructionSetFactory.swift` |
| Capability inspection tool | `HomeAutomationCore/Sources/HomeAutomationAgents/Draft/Tools/AgentInspectCandidateCommandTool.swift` |
| Draft generation agent | `HomeAutomationCore/Sources/HomeAutomationAgents/Draft/DraftGeneration/DraftGenerationAgent.swift` |
| Capability/command validation | `HomeAutomationCore/Sources/HomeAutomationAgents/Safety/Support/AgentCommandValidator.swift` |
| Parameter and risk validation | `HomeAutomationCore/Sources/HomeAutomationCore/HomeAutomation/HomeSafetyAndParameterPolicy.swift` |

## High-Level Architecture

```mermaid
flowchart TB
    User["User command"] --> Graph["GraphScheduler direct-command DAG"]

    Graph --> NLU["NLU Agents\nLanguage, Domain, IntentFamily,\nDeviceType, SlotExtraction, Risk"]
    NLU --> State["HomeResolutionState\nintent families, device types,\nrooms, values, modes, risk"]

    State --> IntentMap["IntentCapabilityMap\nbroad capability hints"]
    State --> CandidateRetrieval["CandidateRetrievalAgent"]
    IntentMap --> CapabilityKnowledge["CapabilityKnowledgeAgent"]

    CandidateRetrieval --> Registry["MockHomeDeviceRegistry\nHomeCandidateRecord capabilities\nsupportedCommands, modes, state"]
    Registry --> CandidateRanking["CandidateRankingAgent\nscopes by room/type and scores\ncapability compatibility"]
    CandidateRanking --> CandidateHydration["CandidateHydrationAgent\nfull candidate records"]

    CapabilityKnowledge --> CanonicalRegistry["HomeCapabilityRegistry\ncommands, attributes,\nranges, enum values, risk"]
    CanonicalRegistry --> KnowledgeSnippets["Canonical capability snippets"]

    CandidateHydration --> InstructionComposer["InstructionComposerAgent\nAgentInstructionSetFactory"]
    KnowledgeSnippets --> InstructionComposer
    IntentMap --> InstructionComposer

    InstructionComposer --> Tools["Draft Tools\ninspectCandidateCommand\nhydrateCandidateRecords\ngetCurrentDeviceState"]
    Tools --> Registry
    Tools --> CanonicalRegistry

    InstructionComposer --> DraftGeneration["DraftGenerationAgent\nFoundation Model chooses\ncapability + command"]
    DraftGeneration --> Draft["HomeCommandDraft\ncapability, command,\nparameters, targetDeviceID"]

    Draft --> SafetyValidation["SafetyValidationAgent\nAgentCommandValidator"]
    SafetyValidation --> ParameterValidation["ParameterValidationAgent\nHomeParameterValidator"]
    SafetyValidation --> RiskPolicy["HomeRiskPolicy"]

    ParameterValidation --> Final["Accepted capability\nor clarification/unsupported"]
    RiskPolicy --> Final
```

### Important Boundaries

- `IntentCapabilityMap` only produces hints. It does not decide the final capability.
- `CapabilityKnowledgeAgent` retrieves context, but hydrates every retrieved capability through `HomeCapabilityRegistry`, so RAG cannot invent unsupported schema.
- `HomeCandidateRecord.capabilities` and `supportedCommands` are the per-device source of truth.
- `DraftGenerationAgent` chooses the final `capability` and `command`, but only from hydrated candidates and canonical context.
- `AgentCommandValidator` is the final fail-closed gate. Unsupported capability/command combinations are rejected.

## Class Diagram

```mermaid
classDiagram
    class HomeCapabilityDefinition {
        +String id
        +String displayName
        +String[] commands
        +String[] attributeNames
        +ClosedRange numericRange
        +String[] enumValues
        +HomeAutomationRiskLevel riskLevel
    }

    class HomeCapabilityRegistry {
        +definitions: Map~String, HomeCapabilityDefinition~
        +riskLevel(for capability)
    }

    class IntentCapabilityMap {
        +capabilities(for intent)
        +capabilities(for intents)
    }

    class HomeResolutionState {
        +language
        +domain
        +intent
        +deviceType
        +slots
        +risk
    }

    class HomeCandidateRecord {
        +String id
        +String displayName
        +String deviceType
        +String room
        +String[] capabilities
        +Map~String, String[]~ supportedCommands
        +String[] supportedModes
        +Map~String, String~ currentState
        +HomeAutomationRiskLevel riskLevel
        +compactView()
    }

    class HomeCompactCandidateView {
        +String id
        +String label
        +String deviceType
        +String room
        +String[] shortCapabilities
    }

    class CandidateRetrievalAgent {
        +run(CandidateRetrievalInput)
    }

    class CandidateRankingAgent {
        +run(CandidateRankingInput)
    }

    class HomeCandidateResolverSupport {
        +resolveCandidates()
        -deterministicAggregation()
        -scopedCandidates()
    }

    class CandidateHydrationAgent {
        +run(CandidateHydrationInput)
    }

    class CapabilityKnowledgeAgent {
        +run([String])
        -nluHints()
    }

    class KnowledgeSnippet {
        +sourceID
        +content
        +score
        +metadata
    }

    class AgentInstructionSetFactory {
        +makePackage()
        +makePackageWithRAG()
        -hydrateCapabilities()
        -instructionText()
        -promptText()
    }

    class AgentToolProvider {
        +tools(for input)
        +estimatedOutputCharacters()
    }

    class AgentInspectCandidateCommandTool {
        +call(Arguments)
    }

    class DraftGenerationAgent {
        +run(HomeModelInstructionPackage)
    }

    class HomeCommandDraft {
        +HomeAutomationIntent intent
        +String targetDeviceID
        +String capability
        +String command
        +HomeResolvedParameter[] parameters
        +Bool needsClarification
        +Bool requiresConfirmation
    }

    class AgentCommandValidator {
        +validate(HomeCommandDraft, HomeFinalResolutionInput)
    }

    class HomeParameterValidator {
        +validate(parameters, capability, command, device)
    }

    class HomeRiskPolicy {
        +requiresConfirmation(intent, capability, deviceType, candidateRisk, command)
    }

    HomeCapabilityRegistry "1" --> "*" HomeCapabilityDefinition
    IntentCapabilityMap --> HomeCapabilityRegistry : produces hint IDs
    HomeResolutionState --> IntentCapabilityMap : intent families
    CandidateRetrievalAgent --> HomeCandidateRecord : retrieves candidates
    CandidateRankingAgent --> HomeCandidateResolverSupport : delegates ranking
    HomeCandidateResolverSupport --> HomeCompactCandidateView : scores views
    CandidateHydrationAgent --> HomeCandidateRecord : hydrates IDs
    CapabilityKnowledgeAgent --> IntentCapabilityMap : NLU capability hints
    CapabilityKnowledgeAgent --> HomeCapabilityRegistry : hydrates RAG hits
    CapabilityKnowledgeAgent --> KnowledgeSnippet : emits canonical snippets
    AgentInstructionSetFactory --> KnowledgeSnippet : prompt context
    AgentInstructionSetFactory --> HomeCandidateRecord : hydrated candidates
    AgentInstructionSetFactory --> AgentToolProvider : tools
    AgentToolProvider --> AgentInspectCandidateCommandTool : provides
    AgentInspectCandidateCommandTool --> HomeCandidateRecord : checks device support
    AgentInspectCandidateCommandTool --> HomeCapabilityRegistry : checks canonical facts
    DraftGenerationAgent --> HomeCommandDraft : produces final draft
    HomeCommandDraft --> AgentCommandValidator : validated by
    AgentCommandValidator --> HomeCandidateRecord : device capabilities
    AgentCommandValidator --> HomeRiskPolicy : confirmation
    AgentCommandValidator --> HomeParameterValidator : params
    HomeParameterValidator --> HomeCapabilityRegistry : ranges and enums
```

## Capability Matching Flow

```mermaid
flowchart TD
    Start["Start: user command"] --> Routing["OperationDetectionAgent extracts language, domain, operation routing"]
    Routing --> ParallelNLU["Direct Graph runs SemanticNLUAgent, SlotExtractionAgent, RiskClassificationAgent in parallel"]
    ParallelNLU --> State["HomeResolutionState"]

    State --> HintMap["IntentCapabilityMap maps intent families to possible capabilities"]
    HintMap --> CapabilityRAG["CapabilityKnowledgeAgent retrieves capability chunks"]
    CapabilityRAG --> HydrateCanon{"Capability ID exists in\nHomeCapabilityRegistry?"}
    HydrateCanon -->|No| DropRAG["Drop invented or stale RAG hit"]
    HydrateCanon -->|Yes| CanonSnippet["Emit canonical commands, attributes,\nenums, range, risk"]

    State --> Retrieve["CandidateRetrievalAgent queries device registry and device RAG"]
    Retrieve --> Rank["CandidateRankingAgent scopes by room/type\nthen scores capability compatibility"]
    Rank --> Ambiguous{"One clear target?"}
    Ambiguous -->|No| ClarifyTarget["Needs clarification:\nwhich device?"]
    Ambiguous -->|Yes| Hydrate["CandidateHydrationAgent returns full HomeCandidateRecord"]

    Hydrate --> Prompt["InstructionComposer builds package:\nuser text, NLU hints, selected candidate,\ncanonical capabilities, tools"]
    CanonSnippet --> Prompt

    Prompt --> Model["DraftGenerationAgent Foundation Model"]
    Model --> ToolCall{"Need support check,\nmode, range, state?"}
    ToolCall -->|Yes| InspectTool["inspectCandidateCommand / state tools"]
    InspectTool --> Model
    ToolCall -->|No| Draft["Produce HomeCommandDraft"]
    Model --> Draft

    Draft --> HasTarget{"targetDeviceID present?"}
    HasTarget -->|No| ClarifyDevice["Clarify target device"]
    HasTarget -->|Yes| DeviceSupportsCap{"Selected device contains\ndraft.capability?"}

    DeviceSupportsCap -->|No| UnsupportedCap["Unsupported:\ndevice does not support capability"]
    DeviceSupportsCap -->|Yes| SupportsCommand{"supportedCommands[capability]\ncontains draft.command?"}

    SupportsCommand -->|No| RelativeAllowed{"Relative change and\nsetter exists?"}
    RelativeAllowed -->|No| UnsupportedCommand["Unsupported:\ncommand unavailable"]
    RelativeAllowed -->|Yes| ValidateParams["Validate parameters"]
    SupportsCommand -->|Yes| ValidateParams

    ValidateParams --> ParamOK{"Range/enum params valid?"}
    ParamOK -->|No| ClarifyParams["Clarify invalid/missing value"]
    ParamOK -->|Yes| RiskCheck{"High risk capability,\ndevice, or command?"}

    RiskCheck -->|Yes| Confirmation["Requires confirmation"]
    RiskCheck -->|No| Accepted["Capability accepted\nreadyToExecute or automation action resolved"]
```

## Sequence Diagram: Direct Command Capability Matching

```mermaid
sequenceDiagram
    actor User
    participant Orchestrator as HomeCommandOrchestrator
    participant Scheduler as GraphScheduler
    participant NLU as NLU Agents
    participant CapMap as IntentCapabilityMap
    participant CapKnowledge as CapabilityKnowledgeAgent
    participant CapRegistry as HomeCapabilityRegistry
    participant Retrieval as CandidateRetrievalAgent
    participant Registry as MockHomeDeviceRegistry
    participant Ranking as CandidateRankingAgent
    participant Hydration as CandidateHydrationAgent
    participant Composer as InstructionComposerAgent
    participant Tools as Draft Tools
    participant DraftGen as DraftGenerationAgent
    participant Validator as SafetyValidationAgent
    participant Params as ParameterValidationAgent

    User->>Orchestrator: "Turn on bedroom AC"
    Orchestrator->>Scheduler: run direct-command graph

    Scheduler->>NLU: language/domain/intent/device/slots/risk
    NLU-->>Scheduler: HomeResolutionState

    Scheduler->>CapMap: capabilities(for: intent families)
    CapMap-->>Scheduler: ["switch", temperature-related hints]

    Scheduler->>CapKnowledge: run(capability hints + context)
    CapKnowledge->>CapRegistry: hydrate retrieved capability IDs
    CapRegistry-->>CapKnowledge: canonical definitions only
    CapKnowledge-->>Scheduler: KnowledgeSnippet list

    Scheduler->>Retrieval: text + HomeResolutionState + memory hints
    Retrieval->>Registry: retrieveCandidates()
    Registry-->>Retrieval: HomeCandidateRecord candidates
    Retrieval-->>Scheduler: retrieved candidates

    Scheduler->>Ranking: compact candidates + NLU hints
    Ranking-->>Scheduler: finalCandidateIDs or clarification

    Scheduler->>Hydration: hydrate selected IDs
    Hydration->>Registry: allDevices()
    Registry-->>Hydration: full HomeCandidateRecord
    Hydration-->>Scheduler: hydrated candidates

    Scheduler->>Composer: HomeFinalResolutionInput
    Composer->>Tools: attach inspectCandidateCommand, hydrateCandidateRecords, state tools
    Composer-->>Scheduler: HomeModelInstructionPackage

    Scheduler->>DraftGen: generate draft
    DraftGen->>Tools: optional inspectCandidateCommand(deviceID, capability, command)
    Tools->>Registry: check selected device
    Tools->>CapRegistry: check capability definition
    Tools-->>DraftGen: supported commands, attributes, modes, ranges, risk
    DraftGen-->>Scheduler: HomeCommandDraft(capability="switch", command="on")

    Scheduler->>Validator: validate draft
    Validator->>Registry: uses hydrated candidate in input
    Validator->>CapRegistry: risk for capability
    Validator-->>Scheduler: readyToExecute / clarification / unsupported / confirmation

    Scheduler->>Params: validate ranges and enum values
    Params->>CapRegistry: numeric ranges and enum values
    Params-->>Scheduler: valid or invalid
```

## Sequence Diagram: Automation Action Capability Matching

Automation creation reuses the same capability matching pipeline for each action description. The automation graph first extracts an automation draft, then `AutomationActionResolutionAgent` fans out nested direct-command graphs for each action.

```mermaid
sequenceDiagram
    actor User
    participant AutoGraph as Automation Creation Graph
    participant DraftAgent as AutomationDraftExtractionAgent
    participant ActionAgent as AutomationActionResolutionAgent
    participant Resolver as AutomationActionResolver
    participant DirectGraph as Nested Direct Command Graph
    participant NLU as NLU + Knowledge + Candidate Agents
    participant DraftGen as DraftGenerationAgent
    participant Validator as Safety/Parameter Validation
    participant Compiler as SmartThingsCompilationAgent

    User->>AutoGraph: "Turn on AC and turn off lamp every day at 7 AM"
    AutoGraph->>DraftAgent: extract schedule and actionDescriptions
    DraftAgent-->>AutoGraph: actionDescriptions ["Turn on AC", "Turn off lamp"]

    AutoGraph->>ActionAgent: resolve action descriptions
    ActionAgent->>Resolver: resolveAll(actions)

    loop each action description
        Resolver->>DirectGraph: run direct-command graph for action text
        DirectGraph->>NLU: infer intent/device/slots/risk and retrieve capability knowledge
        NLU-->>DirectGraph: state, candidates, canonical capability context
        DirectGraph->>DraftGen: choose capability + command
        DraftGen-->>DirectGraph: HomeCommandDraft
        DirectGraph->>Validator: validate capability, command, parameters, risk
        Validator-->>DirectGraph: safe resolved action or clarification
        DirectGraph-->>Resolver: resolved action draft
    end

    Resolver-->>ActionAgent: ordered resolved actions
    ActionAgent-->>AutoGraph: automation resolved actions
    AutoGraph->>Compiler: compile SmartThings rule with validated command actions
```

## Concrete Example: "Turn on bedroom AC"

```mermaid
flowchart LR
    Text["Turn on bedroom AC"] --> Intent["Intent families:\npower + temperature"]
    Intent --> Hints["Capability hints:\nswitch, temperatureMeasurement,\nthermostatCoolingSetpoint,\nairConditionerMode,\nairConditionerFanMode"]
    Text --> Device["Device type:\nairConditioner"]
    Device --> Candidate["Candidate:\nbedroom_ac"]
    Candidate --> DeviceCaps["Device capabilities:\nswitch, temperatureMeasurement,\nthermostatCoolingSetpoint,\nairConditionerMode,\nairConditionerFanMode, ..."]
    DeviceCaps --> Draft["DraftGeneration chooses:\ncapability=switch\ncommand=on"]
    Draft --> Validate["AgentCommandValidator checks:\nbedroom_ac.capabilities contains switch\nsupportedCommands[switch] contains on"]
    Validate --> Accepted["Accepted"]
```

The broad `temperature` intent does not force a temperature-setting capability. Because the command phrase is "turn on", the model can select the `switch` capability if the selected AC supports it. Validation confirms the device supports `switch.on`.

## Concrete Example: "Set bedroom AC to 22 degrees"

```mermaid
flowchart LR
    Text["Set bedroom AC to 22 degrees"] --> Intent["Intent family:\ntemperature"]
    Intent --> Hints["Capability hints:\nthermostatCoolingSetpoint,\nthermostatHeatingSetpoint,\nairConditionerMode,\nairConditionerFanMode,\ntemperatureMeasurement"]
    Text --> Device["Device type:\nairConditioner"]
    Device --> Candidate["Candidate:\nbedroom_ac"]
    Candidate --> DeviceCaps["Device capabilities include:\nthermostatCoolingSetpoint"]
    DeviceCaps --> Draft["DraftGeneration chooses:\ncapability=thermostatCoolingSetpoint\ncommand=setCoolingSetpoint\nparameter=22"]
    Draft --> Param["HomeParameterValidator checks\n22 within 16...30"]
    Param --> Accepted["Accepted"]
```

Here the same selected device can support multiple capabilities. The final capability is resolved from the action semantics plus the selected device's supported capabilities.

## Capability Matching Responsibilities

| Stage | Responsibility | Output | Can Finalize Capability? |
| --- | --- | --- | --- |
| `SemanticNLUAgent` | Extracts intent family and likely device types together | `HomeSemanticNLUResult` | No |
| `SlotExtractionAgent` | Extracts room, values, modes | `HomeSlotExtractionResult` | No |
| `IntentCapabilityMap` | Converts intent family into capability hints | `[String]` capability IDs | No |
| `CapabilityKnowledgeAgent` | Retrieves and hydrates canonical capability facts | `KnowledgeSnippet` | No |
| `CandidateRetrievalAgent` | Retrieves devices whose names/types/capabilities fit hints | `[HomeCandidateRecord]` | No |
| `CandidateRankingAgent` | Chooses target candidate IDs | `HomeCandidateAggregationResult` | No |
| `CandidateHydrationAgent` | Loads full candidate capabilities and supported commands | `[HomeCandidateRecord]` | No |
| `InstructionComposerAgent` | Builds constrained prompt and tools | `HomeModelInstructionPackage` | No |
| `DraftGenerationAgent` | Chooses `targetDeviceID`, `capability`, `command`, params | `HomeCommandDraft` | Yes, provisional |
| `SafetyValidationAgent` / `AgentCommandValidator` | Verifies selected device supports capability and command | `HomeCommandResolution` | Yes, final |
| `ParameterValidationAgent` | Verifies numeric range and enum values | `Bool` | Confirms final |
| `SmartThingsCompilationAgent` | Converts validated automation actions to rule JSON | `SmartThingsCompilationOutput` | Uses final only |

## Failure Modes and Guardrails

```mermaid
flowchart TD
    Draft["Draft capability decision"] --> MissingDevice{"No selected device?"}
    MissingDevice -->|Yes| ClarifyDevice["needsClarification"]
    MissingDevice -->|No| MissingCapability{"No capability or capability\nnot on device?"}
    MissingCapability -->|Yes| UnsupportedCapability["unsupported"]
    MissingCapability -->|No| MissingCommand{"No command or unsupported command?"}
    MissingCommand -->|Yes| RelativeCheck{"Relative setter available?"}
    RelativeCheck -->|No| UnsupportedCommand["unsupported"]
    RelativeCheck -->|Yes| Params["parameter validation"]
    MissingCommand -->|No| Params
    Params --> BadRange{"Value outside range\nor enum not supported?"}
    BadRange -->|Yes| ClarifyValue["needsClarification"]
    BadRange -->|No| Risk["risk policy"]
    Risk --> HighRisk{"High/critical risk?"}
    HighRisk -->|Yes| Confirm["requiresConfirmation"]
    HighRisk -->|No| Ready["readyToExecute / resolved automation action"]
```

Guardrails:

- RAG context is advisory and must hydrate through `HomeCapabilityRegistry`.
- Candidate IDs selected by the model are constrained to known IDs.
- Draft generation instructions explicitly say not to invent devices, capabilities, commands, modes, or IDs.
- `inspectCandidateCommand` gives the model a compact capability/command/risk lookup before it returns the draft.
- `AgentCommandValidator` rechecks capability support after model generation.
- `HomeParameterValidator` rechecks ranges and enum values using canonical definitions and device supported modes.
- `HomeRiskPolicy` can require confirmation based on device risk, capability risk, intent, or command.

## Current Architectural Observation

The current implementation has a strong validation boundary, but capability matching is distributed. That is good for safety, because the final model choice is checked deterministically, but it can make evaluation harder. For future evaluation, the logger should capture at least these per-run capability signals:

- Intent family output and confidence.
- Intent-derived capability hints.
- Capability RAG query, filters, retrieved capability IDs, and hydrated canonical IDs.
- Candidate list with each candidate's capabilities.
- Draft model's selected `capability` and `command`.
- `inspectCandidateCommand` tool calls and outputs.
- Validation result: accepted, unsupported capability, unsupported command, invalid parameter, or confirmation required.
