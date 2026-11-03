import sqlite3
c = sqlite3.connect('/opt/novagate/server/novagate_auth.db')
try:
    c.execute("INSERT INTO admin_log (admin_user, action, target_type, target_id, detail, created_at) VALUES ('test', 'test', 'test', 'test', 'test', 0)")
    c.execute("ROLLBACK")
    print('WRITE_OK')
except Exception as e:
    print('WRITE_ERROR:', e)
