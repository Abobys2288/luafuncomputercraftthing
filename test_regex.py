import re
line = 'elseif key == keys["end"] then cursorCol = #(lines[cursorLine] or "") + 1'
words = re.findall(r'\b\w+\b', line)
print(words)
print('end' in words)
