content = open('hud_do.gd', 'rb').read()
lines = content.split(b'\n')
new_lines = []
i = 0
removed = 0
while i < len(lines):
    line = lines[i]
    stripped = line.strip()
    
    # Remove lines containing _diag_show() calls - replace with pass at same indent
    if b'_diag_show(' in line:
        indent = line[:len(line) - len(line.lstrip())]
        new_lines.append(indent + b'pass  # DIAG removed')
        removed += 1
        i += 1
        continue
    
    # Remove lines that are just [HUD_DO DIAG] print statements
    if b'[HUD_DO DIAG]' in line:
        removed += 1
        i += 1
        continue
    
    new_lines.append(line)
    i += 1

open('hud_do.gd', 'wb').write(b'\n'.join(new_lines))
print('Removed', removed, 'DIAG-related lines from hud_do.gd')
