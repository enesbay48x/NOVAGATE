import subprocess, psutil

for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
    try:
        if 'godot' in proc.info['name'].lower():
            print('PID:', proc.info['pid'])
            print('Name:', proc.info['name'])
            print('Cmdline:', proc.info['cmdline'])
    except:
        pass