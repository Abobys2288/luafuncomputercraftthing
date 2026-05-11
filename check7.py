content = open(r'C:\Users\Просто челик\luccgames\repo\ccos\desktop.lua', 'r').read()
lines = content.split('\n')

# Find the unclosed string
in_string = False
string_char = None
for i, line in enumerate(lines, 1):
    for j, ch in enumerate(line):
        if in_string:
            if ch == '\\':
                continue  # skip next
            if ch == string_char:
                in_string = False
        else:
            if ch == '"' or ch == "'":
                # Check if it's inside a comment
                stripped = line[:j].strip()
                if stripped.startswith('--'):
                    continue
                in_string = True
                string_char = ch
                start_line = i
                start_col = j

if in_string:
    print(f"Unclosed string starting at line {start_line}, col {start_col}")
    print(f"String char: {string_char}")
    # Print context
    for k in range(max(0, start_line-3), min(len(lines), start_line+3)):
        print(f"  {k+1}: {lines[k][:80]}")
