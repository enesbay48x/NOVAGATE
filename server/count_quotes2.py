with open('server/server_db.py', 'r') as f:
    lines = f.readlines()
for i, line in enumerate(lines, 1):
    if '"""' in line:
        count = line.count('"""')
        print(f'Line {i}: {count} triple quotes')
