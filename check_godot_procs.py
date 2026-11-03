import psutil
for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
    try:
        if 'Godot' in proc.info['name']:
            print('PID:', proc.info['pid'])
            print('Name:', proc.info['name'])
            print('Cmdline:', proc.info['cmdline'])
            print()
    except:
        pass