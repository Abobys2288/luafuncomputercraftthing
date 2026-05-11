import re

content = open(r'C:\Users\Просто челик\luccgames\repo\ccos\desktop.lua', 'r').read()
lines = content.split('\n')

depth = 0
for i, line in enumerate(lines, 1):
    stripped = line.strip()
    if not stripped or stripped.startswith('--'):
        continue
    
    # More accurate: count actual block-opening keywords
    # function, do, then (only after if/repeat, not elseif), repeat
    # elseif does NOT open a new block
    
    # Find all block keywords
    # Use regex to find 'function', 'do', 'then', 'repeat' as whole words
    # But 'then' only counts after 'if' or 'repeat', not 'elseif'
    
    # Simple approach: count opens and closes properly
    words = re.findall(r'\b\w+\b', stripped)
    
    # Check if this line has 'elseif' - if so, don't count 'then'
    has_elseif = 'elseif' in words
    has_if = 'if' in words
    
    for w in words:
        if w == 'function':
            depth += 1
        elif w == 'do':
            depth += 1
        elif w == 'repeat':
            depth += 1
        elif w == 'then':
            # 'then' opens a block only after 'if' or 'repeat', not 'elseif'
            if not has_elseif:
                depth += 1
            # If it's 'elseif ... then', the 'then' doesn't open a new block
            # because elseif is part of the existing if chain
        elif w == 'end':
            depth -= 1
        elif w == 'until':
            depth -= 1
    
    if depth < 0:
        print(f'Line {i}: NEGATIVE depth {depth}: {stripped[:80]}')
        break

print(f'Final depth: {depth}')
if depth > 0:
    print(f'Missing {depth} end(s)')
elif depth < 0:
    print(f'Extra {abs(depth)} end(s)')
else:
    print('Balanced!')
