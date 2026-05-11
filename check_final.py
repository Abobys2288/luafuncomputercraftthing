import re
c = open(r'C:\Users\Просто челик\luccgames\repo\ccos\desktop.lua','r').read()
lines = c.split('\n')
d = 0
for i, l in enumerate(lines, 1):
    stripped = l.strip()
    if not stripped or stripped.startswith('--'):
        continue
    # Remove strings
    cleaned = re.sub(r'"[^"]*"', '""', stripped)
    cleaned = re.sub(r"'[^']*'", "''", cleaned)
    words = re.findall(r'\b\w+\b', cleaned)
    has_elseif = 'elseif' in words
    for w in words:
        if w in ('function', 'do', 'repeat'):
            d += 1
        elif w == 'then':
            if not has_elseif:
                d += 1
        elif w == 'end':
            d -= 1
    if d < 0:
        print(f'Line {i}: NEGATIVE depth {d}: {stripped[:60]}')
        break
print(f'Final depth: {d}')
