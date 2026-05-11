import re

content = open(r'C:\Users\Просто челик\luccgames\repo\ccos\desktop.lua', 'r').read()
lines = content.split('\n')

depth = 0
for i, line in enumerate(lines, 1):
    stripped = line.strip()
    if not stripped or stripped.startswith('--'):
        continue
    
    words = re.findall(r'\b\w+\b', stripped)
    for w in words:
        if w in ('do', 'then', 'function', 'repeat'):
            depth += 1
        elif w == 'end':
            depth -= 1
    
    if depth < 0:
        print(f'Line {i}: NEGATIVE depth {depth}: {stripped[:80]}')
        break
    
    # Print depth at function boundaries
    if 'function ' in stripped and 'desktop.' in stripped:
        print(f'Line {i}: depth={depth} FUNC: {stripped[:60]}')
    if depth == 0 and w == 'end' and i > 10:
        pass  # top-level end

print(f'Final depth: {depth}')
