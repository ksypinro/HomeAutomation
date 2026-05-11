# Candidate Retrieval Optimization Strategy

This document outlines a future architectural refactor to optimize the `CandidateRetrievalAgent` and `MockHomeDeviceRegistry`. The goal is to evolve the candidate selection process from a "Soft Boosting" model to a high-performance "Hard Filtering" model, particularly for homes with a massive number of devices (e.g., >200 devices).

## 1. Current State Assessment
Currently, candidate retrieval relies on two parallel mechanisms:
1. **O(N) Linear Scoring (`MockHomeDeviceRegistry`)**: Iterates over every device in the home, assigning points (+2, +3, +4) based on matching `DeviceTypes` and `Capabilities` mapped from NLU Intent Families.
2. **Semantic RAG Blending**: Appends the NLU tokens to the raw query and relies on the Vector Database to surface semantically similar candidates.

### Limitations of Current State
- **Performance**: O(N) linear scoring across the entire device catalog does not scale efficiently for massive smart-home deployments.
- **Context Pollution**: Soft boosting allows low-scoring but irrelevant devices to occasionally surface if the NLU signal is noisy, leading to unnecessary tokens consumed by the Foundation Model in the Draft generation phase.

## 2. Proposed "Hard Filtering" Architecture

Instead of iterating over all devices and assigning points, the system should use high-confidence NLU signals to completely eliminate invalid candidates *before* scoring or RAG retrieval occurs.

### Phase 1: High-Confidence Hard Gates
When the NLU Agents (`DeviceTypeAgent`, `IntentFamilyAgent`) return results with a confidence score exceeding a strict threshold (e.g., `> 0.95`), the orchestrator applies "Hard Gates".

* **Device Type Gating**: If NLU is >95% confident the user wants a `thermostat`, we perform a set intersection to instantly drop any candidate that is not a `thermostat` or `airConditioner`.
* **Capability Gating**: If NLU is >95% confident the intent family is `.brightness`, we instantly drop any candidate that does not possess the `switchLevel` or `colorControl` capability.

### Phase 2: O(1) Indexing Structures
To support hard filtering efficiently, the `MockHomeDeviceRegistry` should maintain inverted indices (dictionaries) built at initialization:
```swift
// Fast O(1) Lookups
var devicesByType: [String: Set<String>] // e.g., ["light": ["lamp_1", "lamp_2"]]
var devicesByCapability: [String: Set<String>] // e.g., ["switchLevel": ["lamp_1", "blind_1"]]
var devicesByRoom: [String: Set<String>] 
```

The candidate retrieval logic becomes a fast Set Intersection operation:
```swift
let matchedIDs = devicesByType["light"]!.intersection(devicesByRoom["bedroom"]!)
```

### Phase 3: The "Accordion" Fallback Strategy
Hard filtering introduces the risk of "Zero Results" if the NLU makes a mistake. To mitigate this, implement an accordion-style fallback mechanism:

1. **Attempt 1 (Strict)**: Apply Hard Gates for `DeviceType` AND `Capability`.
2. **Attempt 2 (Relaxed)**: If 0 candidates, drop the `Capability` gate and filter only by `DeviceType`.
3. **Attempt 3 (Wide)**: If still 0 candidates, drop all Hard Gates and revert to the legacy O(N) Soft Boosting + RAG blending mechanism.

## 3. Implementation Plan

1. **Update `HomeCandidateRecord` Memory Management**:
   - Ensure the registry builds and caches the `devicesByType`, `devicesByCapability`, and `devicesByRoom` indices during the initial data load.

2. **Modify `CandidateRetrievalAgent`**:
   - Intercept the `CandidateRetrievalInput` and check the `confidence` properties of the `state.deviceType` and `state.intent` objects.
   - Route to `retrieveByStrictFiltering()` if confidence > 0.95.
   - Route to `retrieveBySoftScoring()` otherwise.

3. **Benchmarking Suite**:
   - Create a synthetic home with 10,000 devices.
   - Measure latency and memory overhead comparing the legacy linear scoring vs. the inverted index intersection. Ensure the token context size drops by explicitly filtering out unrelated noise.
