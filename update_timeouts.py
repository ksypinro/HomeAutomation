import os
import re

dir_path = "/Users/samin/Downloads/untitled folder/HomeAutomation/HomeAutomationCore/Sources"

# Pattern to match `public let timeoutNanoseconds: UInt64 = <number>`
pattern = re.compile(r'(public\s+let\s+timeoutNanoseconds:\s*UInt64\s*=\s*)[0-9_]+')

updated_files = 0

for root, dirs, files in os.walk(dir_path):
    for file in files:
        if file.endswith(".swift"):
            filepath = os.path.join(root, file)
            with open(filepath, 'r') as f:
                content = f.read()
            
            # Replace with 60 seconds in nanoseconds
            new_content = pattern.sub(r'\g<1>60_000_000_000', content)
            
            if new_content != content:
                with open(filepath, 'w') as f:
                    f.write(new_content)
                updated_files += 1

print(f"Updated {updated_files} files.")
