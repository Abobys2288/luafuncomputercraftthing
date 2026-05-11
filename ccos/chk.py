import re
c = open(r'C:\Users\Просто челик\luccgames\ccos\desktop.lua','r').read()
d = 0
for l in c.split('\n'):
    has_else = 'elseif' in l
    for w in re.findall(r'\b\w+\b', l.strip()):
        if w in ('do','function','repeat'):
            d += 1
        elif w == 'then' and not has_else:
            d += 1
        elif w == 'end':
            d -= 1
print('OK' if d == 0 else f'ERR: {d}')
