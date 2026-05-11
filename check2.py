import re

content = open(r'C:\Users\Просто челик\luccgames\repo\ccos\desktop.lua', 'r').read()

# Remove all comments
content_clean = re.sub(r'--\[\[.*?\]\]', '', content, flags=re.DOTALL)
content_clean = re.sub(r'--[^\n]*', '', content_clean)

# Count all block opens and closes more carefully
# In Lua: do, then (if/repeat), function, for, while open blocks
# end closes any block
# else/elseif don't open/close

opens = 0
closes = 0
lines = content_clean.split('\n')

for i, line in enumerate(lines, 1):
    stripped = line.strip()
    if not stripped:
        continue
    
    # Use regex to find whole words
    words = re.findall(r'\b\w+\b', stripped)
    
    for w in words:
        if w in ('do', 'then', 'function', 'repeat'):
            opens += 1
        elif w == 'end':
            closes += 1

print(f'Block opens: {opens}')
print(f'Block closes: {closes}')
print(f'Difference: {opens - closes}')

# Also check for 'return' inside table constructors (common mistake)
# Find lines with 'return' that might be inside a table
in_table = 0
for i, line in enumerate(lines, 1):
    stripped = line.strip()
    if not stripped or stripped.startswith('--'):
        continue
    
    # Count braces
    for ch in stripped:
        if ch == '{':
            in_table += 1
        elif ch == '}':
            in_table -= 1
    
    if in_table > 0 and 'return' in stripped and not stripped.startswith('function'):
        print(f'Line {i}: possible return inside table: {stripped[:60]}')
