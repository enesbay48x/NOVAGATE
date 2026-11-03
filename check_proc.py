import psutil
print("=== Checking PID 35312 ===")
for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
    try:
        if proc.info['pid'] == 35312:
            print('PID:', proc.info['pid'])
            print('Name:', proc.info['name'])
            print('Cmdline:', proc.info['cmdline'])
    except Exception as e:
        print(f'Error: {e}')

print("\n=== Killing all Godot processes ===")
killed = 0
for proc in psutil.process_iter(['pid', 'name']):
    try:
        if proc.info['name'] and 'Godot' in proc.info['name']:
            print('Killing PID', proc.info['pid'], ':', proc.info['name'])
            proc.kill()
            killed += 1
    except Exception as e:
        pass
print('Total killed:', killed)