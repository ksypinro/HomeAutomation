import os

filepath = "/Users/samin/Downloads/untitled folder/HomeAutomation/HomeAutomationCore/Sources/HomeAutomationOrchestrator/OrchestratorMetricsCollector.swift"
with open(filepath, 'r') as f:
    lines = f.readlines()

models_lines = []
actor_lines = []

actor_started = False
for line in lines:
    if "public actor OrchestratorMetricsCollector" in line:
        actor_started = True
        actor_lines.append("import Foundation\nimport OSLog\n\n")
    if actor_started:
        actor_lines.append(line)
    else:
        models_lines.append(line)

with open("/Users/samin/Downloads/untitled folder/HomeAutomation/HomeAutomationCore/Sources/HomeAutomationOrchestrator/OrchestratorMetrics.swift", 'w') as f:
    f.writelines(models_lines)

with open(filepath, 'w') as f:
    f.writelines(actor_lines)

print("Split completed.")
