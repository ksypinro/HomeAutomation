import os
import re

dir_path = "/Users/samin/Downloads/untitled folder/HomeAutomation/HomeAutomationCore/Sources/HomeAutomationOrchestrator"

pattern = re.compile(r'ResolutionContextPatchKey\.([a-zA-Z0-9_]+)')
skip_keys = ["registry"]

for root, dirs, files in os.walk(dir_path):
    for file in files:
        if file.endswith(".swift"):
            filepath = os.path.join(root, file)
            with open(filepath, 'r') as f:
                content = f.read()
            
            # Don't replace in the enum definition file itself
            if "ResolutionContextPatchKey.swift" in file:
                continue
                
            def replacer(match):
                if match.group(1) in skip_keys:
                    return match.group(0)
                return f"ResolutionContextPatchKey.{match.group(1)}.rawValue"
                
            new_content = pattern.sub(replacer, content)
            
            if new_content != content:
                with open(filepath, 'w') as f:
                    f.write(new_content)
                print(f"Updated {filepath}")
