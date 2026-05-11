content = open(r'C:\Users\Просто челик\luccgames\repo\ccos\desktop.lua', 'r').read()

# Check for unclosed strings
# Count quotes (simplified - doesn't handle escaped quotes)
in_string = False
string_char = None
i = 0
while i < len(content):
    ch = content[i]
    if in_string:
        if ch == '\\':
            i += 2  # skip escaped char
            continue
        if ch == string_char:
            in_string = False
    else:
        if ch == '"' or ch == "'":
            in_string = True
            string_char = ch
    i += 1

if in_string:
    print(f"UNCLOSED STRING with {string_char}")
else:
    print("Strings are balanced")

# Also check parentheses
parens = 0
for ch in content:
    if ch == '(':
        parens += 1
    elif ch == ')':
        parens -= 1
    if parens < 0:
        print(f"Negative parens at some point")
        break
print(f"Final paren balance: {parens}")

# Check braces
braces = 0
for ch in content:
    if ch == '{':
        braces += 1
    elif ch == '}':
        braces -= 1
    if braces < 0:
        print(f"Negative braces at some point")
        break
print(f"Final brace balance: {braces}")
