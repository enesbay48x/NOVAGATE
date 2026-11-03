import os, sys, tempfile, threading, time
d = tempfile.mkdtemp()
os.environ["NOVAGATE_DB_PATH"] = os.path.join(d, "t.db")
import server_db as S

def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond: sys.exit(1)

A = 7
# 1) ilk giris
r = S.acquire_session_lock(A, "tokA", "inst1")
check("ilk giris ok, replaced=False", r["ok"] and not r["replaced"] and r["previous_session"] == "")
# 2) ikinci cihaz ayni instance'ta: YENI GIREN KAZANIR
r = S.acquire_session_lock(A, "tokB", "inst1")
check("ikinci giris eskiyi devralir (replaced=True, previous=tokA)", r["ok"] and r["replaced"] and r["previous_session"] == "tokA")
# 3) eski oturum heartbeat: artik sahibi degil
check("eski oturum renew -> owned=False", S.renew_session_lock(A, "tokA") == {"ok": True, "owned": False})
check("yeni oturum renew -> owned=True", S.renew_session_lock(A, "tokB") == {"ok": True, "owned": True})
# 4) eski oturumun kapanis release'i yeni kilidi SILMEZ
S.release_session_lock(A, "tokA")
check("eski release yeni kilidi silmedi", S.renew_session_lock(A, "tokB")["owned"] is True)
# 5) yeni oturum kendi release'i siler
S.release_session_lock(A, "tokB")
check("kendi release kilidi siler", S.renew_session_lock(A, "tokB")["owned"] is False)
# 6) sunucu cokmesi: suresi dolmus kilit girisi ENGELLEMEZ
S.acquire_session_lock(A, "tokOld", "instCrashed")
c = S.get_db(); c.execute("UPDATE session_locks SET expires_at = ? WHERE account_id = ?", (S.now_ts() - 5, A)); c.close()
r = S.acquire_session_lock(A, "tokNew", "instNew")
check("cokme sonrasi bayat kilit: giris engellenmedi (replaced=False)", r["ok"] and not r["replaced"])
# 7) bayat temizlik
c = S.get_db(); c.execute("UPDATE session_locks SET expires_at = ? WHERE account_id = ?", (S.now_ts() - 5, A)); c.close()
check("cleanup_stale_locks suresi dolani siler", S.cleanup_stale_locks("x") == 1)
# 8) YARIS: 25 es zamanli giris
B = 9; N = 25; res = [None]*N; bar = threading.Barrier(N)
def go(i):
    bar.wait(); res[i] = S.acquire_session_lock(B, f"tok{i}", "inst1")
ts = [threading.Thread(target=go, args=(i,)) for i in range(N)]
[t.start() for t in ts]; [t.join() for t in ts]
check("yaris: hepsi ok", all(r and r["ok"] for r in res))
c = S.get_db(); owner = c.execute("SELECT session_token FROM session_locks WHERE account_id=?", (B,)).fetchone()[0]; c.close()
owners = [i for i in range(N) if S.renew_session_lock(B, f"tok{i}")["owned"]]
check(f"yaris: tam 1 sahip ({owner})", len(owners) == 1 and owner == f"tok{owners[0]}")
chain = {r["previous_session"] for r in res if r["previous_session"]}
check("yaris: her devralma zincirde benzersiz bir onceki oturum gosterir", len(chain) == N-1)
print("TUM TESTLER GECTI")
