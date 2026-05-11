content = open(r'C:\Users\Просто челик\luccgames\repo\ccos\desktop.lua', 'r').read()
lines = content.split('\n')

# Simple approach: for each line, count quotes that are not inside strings
# This is tricky, so let's just look for lines with odd number of single quotes
for i, line in enumerate(lines, 1):
    stripped = line.strip()
    if stripped.startswith('--'):
        continue
    
    # Count single quotes (not inside double-quoted strings)
    sq = 0
    dq = 0
    in_sq = False
    in_dq = False
    escaped = False
    
    for ch in stripped:
        if escaped:
            escaped = False
            continue
        if ch == '\\':
            escaped = True
            continue
        if ch == "'" and not in_dq:
            in_sq = not in_sq
            sq += 1
        elif ch == '"' and not in_sq:
            in_dq = not in_dq
            dq += 1
    
    if sq % 2 == 1:
        print(f"Line {i}: odd single quotes ({sq}): {stripped[:80]}")
    if dq % 2 == 1:
        print(f"Line {i}: odd double quotes ({dq}): {stripped[:80]}")
