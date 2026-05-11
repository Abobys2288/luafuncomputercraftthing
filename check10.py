# Try to find the syntax error by parsing the file as Lua would
# We'll simulate a simple Lua parser

content = open(r'C:\Users\Просто челик\luccgames\repo\ccos\desktop.lua', 'r').read()
lines = content.split('\n')

# Remove comments first
cleaned = []
i = 0
while i < len(lines):
    line = lines[i]
    stripped = line.strip()
    
    # Skip single-line comments
    if stripped.startswith('--'):
        i += 1
        continue
    
    # Check for multi-line comment
    if '--[[' in line:
        # Find matching ]]
        full_line = line
        while ']]' not in full_line and i < len(lines) - 1:
            i += 1
            full_line += '\n' + lines[i]
        i += 1
        continue
    
    cleaned.append(line)
    i += 1

# Now parse and track blocks
block_stack = []
depth = 0

for line_num, line in enumerate(cleaned, 1):
    stripped = line.strip()
    if not stripped:
        continue
    
    # Simple tokenization
    import re
    # Remove strings first (replace with placeholder)
    no_strings = re.sub(r'"[^"]*"', '""', stripped)
    no_strings = re.sub(r"'[^']*'", "''", no_strings)
    
    words = re.findall(r'\b\w+\b', no_strings)
    
    for w in words:
        if w in ('function', 'do', 'repeat'):
            depth += 1
            block_stack.append((w, line_num))
        elif w == 'then':
            # Only counts after 'if' or 'repeat', not 'elseif'
            if 'elseif' not in no_strings:
                depth += 1
                block_stack.append((w, line_num))
        elif w == 'end':
            depth -= 1
            if block_stack:
                block_stack.pop()
            if depth < 0:
                print(f"Line {line_num}: EXTRA 'end' (depth={depth})")
                print(f"  Content: {stripped[:80]}")
                print(f"  Block stack top: {block_stack[-5:] if block_stack else 'empty'}")
                break

if depth > 0:
    print(f"Missing {depth} 'end(s)'")
    print(f"Unclosed blocks:")
    for b in block_stack[-10:]:
        print(f"  {b}")
elif depth == 0:
    print("File is syntactically balanced!")
