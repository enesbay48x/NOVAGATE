import re

with open(r'C:\Users\Pc\Downloads\Yeni klasör\main.gd', 'r', encoding='utf-8') as f:
    content = f.read()

print('=== Image.lock() / unlock() ===')
for m in re.finditer(r'\.lock\(\)|\.unlock\(\)', content):
    line = content[:m.start()].count('\n') + 1
    print(f'  Line {line}: {m.group()}')

print()
print('=== gui_get_canvas ===')
for m in re.finditer(r'gui_get_canvas', content):
    line = content[:m.start()].count('\n') + 1
    print(f'  Line {line}')

print()
print('=== anchors[0] / anchors[1] ===')
for m in re.finditer(r'\.anchors\[(0|1)\]', content):
    line = content[:m.start()].count('\n') + 1
    print(f'  Line {line}: {m.group()}')

print()
print('=== set_anchors_and_offsets ===')
for m in re.finditer(r'set_anchors_and_offsets', content):
    line = content[:m.start()].count('\n') + 1
    print(f'  Line {line}')

print()
print('=== yield ===')
for m in re.finditer(r'\byield\b', content):
    line = content[:m.start()].count('\n') + 1
    start = max(0, m.start() - 50)
    end = min(len(content), m.end() + 50)
    print(f'  Line {line}: ...{content[start:end]}...')

print()
print('=== connect old style ===')
for m in re.finditer(r'\.connect\([\s]*\"[^\"]+\"[\s]*,[\s]*self[\s]*,[\s]*\"[^\"]+\"', content):
    line = content[:m.start()].count('\n') + 1
    start = max(0, m.start() - 30)
    end = min(len(content), m.end() + 30)
    print(f'  Line {line}: ...{content[start:end]}...')

print()
print('=== Callable ===')
for m in re.finditer(r'Callable\(self,', content):
    line = content[:m.start()].count('\n') + 1
    start = max(0, m.start() - 30)
    end = min(len(content), m.end() + 30)
    print(f'  Line {line}: ...{content[start:end]}...')