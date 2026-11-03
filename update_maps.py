import sqlite3
c = sqlite3.connect('/opt/novagate/server/novagate_game.db')
cur = c.execute("UPDATE player_data SET map_name='2-1', px=0, pz=0 WHERE account_id IN (SELECT id FROM accounts WHERE faction=2 AND map_name='1-1')")
print("Faction 2 updated:", cur.rowcount)
cur = c.execute("UPDATE player_data SET map_name='3-1', px=0, pz=0 WHERE account_id IN (SELECT id FROM accounts WHERE faction=3 AND map_name='1-1')")
print("Faction 3 updated:", cur.rowcount)
c.commit()
c.close()
print("DB_UPDATE_OK")
