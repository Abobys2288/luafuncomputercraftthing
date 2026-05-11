content = open(r'C:\Users\Просто челик\luccgames\repo\ccos\desktop.lua', 'r').read()

# Track string state across entire file
in_string = False
string_char = None
escaped = False
line_num = 1
col = 0

for i, ch in enumerate(content):
    if ch == '\n':
        line_num += 1
        col = 0
        continue
    
    if escaped:
        escaped = False
        continue
    
    if ch == '\\':
        escaped = True
        continue
    
    if in_string:
        if ch == string_char:
            in_string = False
    else:
        if ch == '"' or ch == "'":
            # Check if inside comment
            # Look backwards for --[[
            pos = i
            # Simple check: is there a -- before this on the same line?
            line_start = content.rfind('\n', 0, pos) + 1
            line_prefix = content[line_start:pos].strip()
            if line_prefix.startswith('--'):
                continue
            in_string = True
            string_char = ch
            start_pos = pos
            start_line = line_num

if in_string:
    print(f"UNCLOSED STRING with '{string_char}' at line {start_line}")
    # Show context
    lines = content.split('\n')
    for k in range(max(0, start_line-2), min(len(lines), start_line+5)):
        marker = " >>>" if k+1 == start_line else "    "
        print(f"{marker} {k+1}: {lines[k][:100]}")
else:
    print("All strings are properly closed")
