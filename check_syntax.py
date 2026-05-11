import re

content = open(r'C:\Users\Просто челик\luccgames\repo\ccos\desktop.lua', 'r').read()
lines = content.split('\n')

# Simple block tracker
depth = 0
for i, line in enumerate(lines, 1):
    stripped = line.strip()
    if stripped.startswith('--'):
        continue
    
    # Count block keywords
    words = stripped.split()
    for w in words:
        if w in ('do', 'then', 'function', 'repeat'):
            depth += 1
        elif w == 'end':
            depth -= 1
    
    if depth < 0:
        print(f'Line {i}: depth went negative ({depth}): {stripped[:80]}')
        break

print(f'Final depth: {depth}')
if depth > 0:
    print(f'Missing {depth} end(s) at end of file')
elif depth < 0:
    print(f'Extra {abs(depth)} end(s)')
else:
    print('Balanced')
