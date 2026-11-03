#!/usr/bin/env python3
"""server_db.py icindeki 'server/debug_verify.log' hata ayiklama yazimlarini kaldirir.
Bu yazimlar goreli yol kullandigi icin, calisma klasorunde 'server/' yoksa gecerli token'lar
bile reddediliyordu. Yazimlar guvenli logging cagrilarina cevrilir (dosyaya yazmaz, hata firlatmaz).
Kullanim: python3 patch_server_db.py /opt/novagate/server/server_db.py"""
import re, sys, shutil, py_compile, time

path = sys.argv[1]
src = open(path, encoding="utf-8").read()
if "debug_verify.log" not in src:
    print("Zaten temiz: debug_verify.log yazimi yok."); sys.exit(0)

shutil.copy(path, path + ".yama_oncesi_" + time.strftime("%Y%m%d%H%M%S"))

# with open("server/debug_verify.log", "a") as f:\n    f.write(<ifade>)\n [f.flush()\n]
pat = re.compile(
    r'^(?P<ind>[ \t]*)with open\("server/debug_verify\.log", "a"\) as f:\n'
    r'(?P<body>(?:(?P=ind)[ \t]+.*\n)+)', re.M)

def repl(m):
    ind = m.group("ind")
    out = []
    for line in m.group("body").splitlines():
        s = line.strip()
        w = re.match(r'f\.write\((.*)\)\s*$', s)
        if w:
            out.append(f"{ind}_vlog({w.group(1)})")
        # f.flush() ve diger satirlar atilir
    return "\n".join(out) + ("\n" if out else "")

new, n = pat.subn(repl, src)

helper = '''

def _vlog(msg) -> None:
    """Token dogrulama izleri: dosyaya yazmaz, hicbir kosulda hata firlatmaz."""
    try:
        log.info("verify: %s", str(msg).strip())
    except Exception:
        pass

'''
# yardimci fonksiyonu 'def verify_and_consume_token' oncesine ekle
idx = new.index("def verify_and_consume_token")
new = new[:idx].rstrip("\n") + "\n" + helper + "\n" + new[idx:]
open(path, "w", encoding="utf-8").write(new)
py_compile.compile(path, doraise=True)
print(f"Yama tamam: {n} yazim degistirildi, sozdizimi OK. Yedek: {path}.yama_oncesi_*")
