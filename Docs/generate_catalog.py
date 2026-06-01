import json
import os

catalog_path = '/Users/samin/Downloads/untitled folder/HomeAutomation/HomeAutomationCore/Sources/HomeAutomationCore/Resources/home_automation_capability_catalog.json'
output_dir = '/Users/samin/.gemini/antigravity-ide/brain/79e7925d-2626-41e1-ab24-2f555959f170'
output_path = os.path.join(output_dir, 'capability_catalog.md')

with open(catalog_path) as f:
    data = json.load(f)

# Define capability grouping mapping
cap_groups = {
    'Lighting & Power': [
        'switch', 'switchLevel', 'colorControl', 'colorTemperature', 'powerMeter', 'energyMeter', 'battery'
    ],
    'Climate & HVAC': [
        'temperatureMeasurement', 'relativeHumidityMeasurement', 'thermostatMode', 'thermostatFanMode', 
        'thermostatCoolingSetpoint', 'thermostatHeatingSetpoint', 'airConditionerMode', 'fanSpeed', 
        'airQualitySensor', 'filterStatus', 'carbonDioxideMeasurement'
    ],
    'Safety & Sensors': [
        'carbonMonoxideDetector', 'smokeDetector', 'contactSensor', 'motionSensor', 'occupancySensor', 
        'illuminanceMeasurement', 'tamperAlert', 'waterSensor', 'soundDetection'
    ],
    'Security & Access': [
        'lock', 'lockCodes', 'doorControl', 'garageDoorControl', 'securitySystem'
    ],
    'Openings & Motorized': [
        'windowShade', 'windowShadeLevel', 'rotation', 'valve'
    ],
    'Water & Gardening': [
        'sprinkler', 'fill', 'dispense'
    ],
    'Appliances & Cooking': [
        'startStop', 'runCycle', 'mode', 'toggle', 'timer', 'cook', 'ovenSetpoint', 'robotCleanerMovement', 'locator'
    ],
    'Media & Entertainment': [
        'cameraStream', 'imageCapture', 'audioVolume', 'mediaPlayback', 'mediaInputSource', 'appSelector', 
        'remoteButton', 'channel'
    ],
    'Networking & System': [
        'reboot', 'statusReport', 'softwareUpdate'
    ],
    'Routines & Scenes': [
        'routine', 'scene'
    ]
}

# Reverse mapping for grouping lookup
id_to_group = {}
for group_name, cap_ids in cap_groups.items():
    for cid in cap_ids:
        id_to_group[cid] = group_name

# Gather capabilities by group
grouped_caps = {g: [] for g in cap_groups.keys()}
grouped_caps['Other / Uncategorized'] = []

for c in data['capabilities']:
    cid = c['id']
    group = id_to_group.get(cid, 'Other / Uncategorized')
    grouped_caps[group].append(c)

# Gather device types by category
grouped_devs = {}
for d in data['deviceTypes']:
    cat = d['category']
    # Capitalize category name for display
    display_cat = cat.replace('_', ' ').title()
    if display_cat not in grouped_devs:
        grouped_devs[display_cat] = []
    grouped_devs[display_cat].append(d)

# Write MD
md = []
md.append('# HomeAutomation Core Capability & Device Type Catalog\n')

md.append('> [!NOTE]')
md.append(f'> **Schema Version:** `{data.get("schemaVersion")}` | **Generated:** `{data.get("generatedAt")}`')
md.append(f'> **System Summary:** Supports `{len(data["capabilities"])}` unified capabilities and `{len(data["deviceTypes"])}` device types.')
md.append('>\n> This catalog is a standardized ontology for home automation devices and capabilities, normalized from major smart home ecosystems. It is used by the `HomeAutomationKnowledgeBase` and agent natural-language parsing layers.\n')

md.append('## Ecosystem Normalization Source platforms\n')
md.append('The capability model is normalized across multiple ecosystems. Below is the source documentation and mapping rules:\n')

for sn in data.get('sourceNotes', []):
    client = sn['client']
    notes = sn['notes']
    urls = sn.get('urls', [])
    urls_md = ", ".join([f"[Documentation]({u})" for u in urls])
    md.append(f'- **{client}** ({urls_md}): {notes}')

md.append('\n### Normalization Notes\n')
for n in data.get('normalizationNotes', []):
    md.append(f'- {n}')

md.append('\n---\n')
md.append('## Table of Contents\n')
md.append('1. [Capabilities Reference](#1-capabilities-reference)')
for group_name in cap_groups.keys():
    anchor = group_name.lower().replace('&', '').replace('  ', ' ').replace(' ', '-')
    md.append(f'   - [{group_name}](#{anchor})')
md.append('2. [Device Types Reference](#2-device-types-reference)')
for cat in sorted(grouped_devs.keys()):
    anchor = cat.lower().replace('&', '').replace('  ', ' ').replace(' ', '-')
    md.append(f'   - [{cat}](#{anchor})')

md.append('\n---\n')
md.append('## 1. Capabilities Reference\n')
md.append('Capabilities represent standard device states, read-only metrics, and control interfaces. They define the commands, value ranges, and security risk levels.\n')

def format_value_type(c):
    vtype = c['valueType']
    if c['numericRange']:
        return f"`numeric` ({c['numericRange'][0]}–{c['numericRange'][1]})"
    elif c['enumValues']:
        return f"`enum` ({', '.join(f'\"{v}\"' for v in c['enumValues'])})"
    return f"`{vtype}`"

def format_risk(risk):
    if risk == 'high':
        return '🔴 **High Risk**'
    elif risk == 'medium':
        return '🟡 **Medium Risk**'
    return '🟢 Low Risk'

# Generate capabilities tables
for group_name in list(cap_groups.keys()) + ['Other / Uncategorized']:
    caps_in_group = grouped_caps[group_name]
    if not caps_in_group:
        continue
    md.append(f'### {group_name}\n')
    md.append('| Capability ID | Display Name | Commands | Value Type / Range / Enums | Risk Level |')
    md.append('| :--- | :--- | :--- | :--- | :--- |')
    for c in sorted(caps_in_group, key=lambda x: x['id']):
        cmds = ', '.join(f'`{cmd}`' for cmd in c['commands']) if c['commands'] else '*Read-only*'
        vtype = format_value_type(c)
        risk = format_risk(c['riskLevel'])
        md.append(f'| `{c["id"]}` | {c["displayName"]} | {cmds} | {vtype} | {risk} |')
    md.append('\n')

md.append('\n---\n')
md.append('## 2. Device Types Reference\n')
md.append('Device types categorize physical or virtual equipment, mapping them to required capabilities, recommended capabilities, and optional capabilities.\n')

# Check if there are high risk device types and show an alert
high_risk_devs = [d['displayName'] for d in data['deviceTypes'] if d['riskLevel'] == 'high']
if high_risk_devs:
    md.append('> [!WARNING]')
    md.append('> **High Risk Device Types Enabled:** control of certain equipment carries higher safety/security risk levels. Actions on these devices (e.g. unlocking a door, opening a valve, or turning on an oven) require extra agent verification and safety checks.')
    md.append(f'> High Risk Devices: {", ".join(f"`{d}`" for d in sorted(high_risk_devs))}\n')

for cat in sorted(grouped_devs.keys()):
    devs_in_cat = grouped_devs[cat]
    md.append(f'### {cat}\n')
    md.append('| Device Type ID | Display Name | Required Capabilities | Recommended Capabilities | Risk Level |')
    md.append('| :--- | :--- | :--- | :--- | :--- |')
    for d in sorted(devs_in_cat, key=lambda x: x['id']):
        req = ', '.join(f'`{rc}`' for rc in d['requiredCapabilities']) if d['requiredCapabilities'] else '*None*'
        rec = ', '.join(f'`{rc}`' for rc in d['recommendedCapabilities']) if d['recommendedCapabilities'] else '*None*'
        risk = format_risk(d['riskLevel'])
        md.append(f'| `{d["id"]}` | {d["displayName"]} | {req} | {rec} | {risk} |')
    md.append('\n')

# Write file
os.makedirs(output_dir, exist_ok=True)
with open(output_path, 'w') as f:
    f.write('\n'.join(md))

print(f'Catalog generated successfully at {output_path}!')
print(f'File size: {os.path.getsize(output_path)} bytes')
