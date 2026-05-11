import re
c = open(r'C:\Users\Просто челик\luccgames\repo\ccos\desktop.lua','r').read()
d = 0
for l in c.split('\n'):
    for w in re.findall(r'\b\w+\b', l.strip()):
        if w in ('do','then','function','repeat'):
            d += 1
        elif w == 'end':
            d -= 1
print('Balanced' if d == 0 else f'Unbalanced: {d}')
