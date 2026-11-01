# Kullanim:  main.gd'nin bulundugu klasorde   python menzil_uygula.py
# main.gd'ye sabit gorus menzili baglantisini ekler (PC + mobil). Once main.gd.menzil_yedek adinda yedek alir.
# Iki kez calistirmak zararsizdir. arkaplan_uygula.py calistirilmis olsun ya da olmasin calisir.
import os, sys
p = "main.gd"
if not os.path.exists(p):
    sys.exit("main.gd bulunamadi: bu dosyayi main.gd ile ayni klasorde calistir.")
raw = open(p, "rb").read().decode("utf-8")
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")
if "MapBg.apply_vision" in s:
    sys.exit("Zaten uygulanmis. Degisiklik yapilmadi.")
if "const MapBg" not in s:
    old = 'const MAP_TEX := "res://assets/maps/%s.jpg"\n'
    if s.count(old) != 1:
        sys.exit("MAP_TEX satiri bulunamadi (main.gd degismis olabilir).")
    s = s.replace(old, old + 'const MapBg := preload("res://map_bg.gd")\n')
old = "\t_update_bars3d()\n\t_update_bg()\n"
if s.count(old) != 1:
    sys.exit("_process icindeki _update_bars3d()/_update_bg() satirlari bulunamadi (main.gd degismis olabilir).")
s = s.replace(old, old + "\tMapBg.apply_vision(self)\n")
open(p + ".menzil_yedek", "wb").write(raw.encode("utf-8"))
open(p, "wb").write((s.replace("\n", "\r\n") if crlf else s).encode("utf-8"))
print("Tamam: main.gd guncellendi (yedek: main.gd.menzil_yedek)")
