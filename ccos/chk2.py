import re
c = open(r'C:\Users\Просто челик\luccgames\ccos\desktop.lua','r').read()
lines = c.split('\n')
d = 0
for i, l in enumerate(lines, 1):
    has_else = 'elseif' in l
    for w in re.findall(r'\b\w+\b', l.strip()):
        if w in ('do','function','repeat'):
            d += 1
        elif w == 'then' and not has_else:
            d += 1
        elif w == 'end':
            d -= 1
    if d < 0:
        print(f'Line {i}: NEGATIVE {d}: {l.strip()[:60]}')
        break
    if l.strip().startswith('function '):
        print(f'Line {i}: depth={d} {l.strip()[:50]}')
print(f'Final: {d}')
