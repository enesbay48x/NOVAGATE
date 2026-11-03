import subprocess

# Start Godot dedicated server with output to file
log_file = open('C:\\Users\\Pc\\Downloads\\Yeni klasör\\godot_server.log', 'w')
p = subprocess.Popen([
    'C:\\Users\\Pc\\Desktop\\Godot_v4.7.2-stable_win64.exe',
    '--path', 'C:/Users/Pc/Downloads/Yeni klasör',
    '--server'
], creationflags=subprocess.CREATE_NEW_CONSOLE, stdout=log_file, stderr=log_file)
print(f'Godot dedicated server PID: {p.pid}')
print(f'Log file: {log_file.name}')
print('Wait 3 seconds then check log...')