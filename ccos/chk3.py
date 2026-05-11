import re
c = open(r'C:\Users\Просто челик\luccgames\ccos\desktop.lua','r').read()
lines = c.split('\n')
d = 0
for i, l in enumerate(lines, 1):
    stripped = l.strip()
    if not stripped or stripped.startswith('--'):
        continue
    cleaned = re.sub(r'"[^"]*"', '""', stripped)
    cleaned = re.sub(r"'[^']*'", "''", cleaned)
    words = re.findall(r'\b\w+\b', cleaned)
    has_else = 'elseif' in cleaned
    for w in words:
        if w in ('function','do','repeat'):
            d += 1
        elif w == 'then' and not has_else:
            d += 1
        elif w == 'end':
            d -= 1
    if i >= 560 and i <= 610:
        print(f'Line {i}: d={d} | {stripped[:70]}')
    if d < 0:
        print(f'NEGATIVE at line {i}')
        break
