lines = open('/opt/novagate/server/server_db.py').readlines()
new_func = open('/tmp/server_db_fixed.py').read()
# Lines 606-744 (1-indexed) = indices 605-743 (0-indexed)
# Start at index 605 (line 606), end before index 744 (line 745 = release_session_lock)
new_lines = lines[:605] + [new_func + '\n'] + lines[744:]
open('/opt/novagate/server/server_db.py', 'w').writelines(new_lines)
print('REPLACED OK')
