content = open(r'C:\Users\Просто челик\luccgames\repo\ccos\desktop.lua', 'r').read()
lines = content.split('\n')

# Check for 'end' inside strings or as variable name
for i, line in enumerate(lines, 1):
    stripped = line.strip()
    if '"end"' in stripped or "'end'" in stripped:
        print(f'Line {i}: end in string: {stripped[:60]}')
    if 'endif' in stripped or 'endfor' in stripped or 'endwhile' in stripped:
        print(f'Line {i}: compound end: {stripped[:60]}')

# Also check for lines that are just 'end' with different whitespace
depth = 0
for i, line in enumerate(lines, 1):
    stripped = line.strip()
    if not stripped or stripped.startswith('--'):
        continue
    words = stripped.split()
    for w in words:
        if w in ('do', 'then', 'function', 'repeat'):
            depth += 1
        elif w == 'end':
            depth -= 1
    if i == 499:
        print(f'Line 499 (end of run): depth={depth}')
        break

print(f'Depth at line 499: {depth}')
