import sqlite3
conn = sqlite3.connect('server/novagate_game.db')
tables = conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
print('Tables:', [t[0] for t in tables])
try:
    rows = conn.execute('SELECT COUNT(*) FROM used_tokens').fetchone()
    print('used_tokens count:', rows[0])
except Exception as e:
    print('used_tokens error:', e)
conn.close()
