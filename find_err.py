import re
c = open(r'C:\Users\Просто челик\luccgames\repo\ccos\desktop.lua','r').read()
lines = c.split('\n')
d = 0
for i, l in enumerate(lines, 1):
    for w in re.findall(r'\b\w+\b', l.strip()):
        if w in ('do','then','function','repeat'):
            d += 1
        elif w == 'end':
            d -= 1
    if d < 0:
        print(f'Line {i}: NEGATIVE depth {d}: {l.strip()[:60]}')
        break
    if 'function desktop.' in l and 'then' not in l:
        pass
    # Print depth at key points
    if l.strip().startswith('function desktop.'):
        print(f'Line {i}: depth={d} FUNC: {l.strip()[:50]}')
print(f'Final depth: {d}')
