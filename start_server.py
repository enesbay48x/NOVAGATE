import subprocess

# Start Godot dedicated server
p = subprocess.Popen([
    'C:\\Users\\Pc\\Desktop\\Godot_v4.7.2-stable_win64.exe',
    '--path', 'C:/Users/Pc/Downloads/Yeni klasör',
    '--server'
], creationflags=subprocess.CREATE_NEW_CONSOLE)
print(f'Godot dedicated server PID: {p.pid}')