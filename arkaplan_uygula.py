# Kullanim:  main.gd'nin bulundugu klasorde   python arkaplan_uygula.py
# main.gd'ye 4 kucuk baglanti ekler. Once main.gd.arkaplan_yedek adinda yedek alir. Iki kez calistirmak zararsizdir.
import os, sys
p = "main.gd"
if not os.path.exists(p):
    sys.exit("main.gd bulunamadi: bu dosyayi main.gd ile ayni klasorde calistir.")
raw = open(p, "rb").read().decode("utf-8")
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")
if "MapBg" in s:
    sys.exit("Zaten uygulanmis (MapBg bulundu). Degisiklik yapilmadi.")
def rep(old, new):
    global s
    if s.count(old) != 1:
        sys.exit("Beklenen satir bulunamadi (main.gd degismis olabilir):\n" + old)
    s = s.replace(old, new)
rep('const MAP_TEX := "res://assets/maps/%s.jpg"\n',
    'const MAP_TEX := "res://assets/maps/%s.jpg"\nconst MapBg := preload("res://map_bg.gd")\n')
rep("\tsh.code = SPACE_BG_SHADER\n", "\tsh.code = MapBg.SHADER\n")
rep("\tbg_tex = _tex(MAP_TEX % name)\n", "\tbg_tex = _tex(MAP_TEX % name)\n\tMapBg.set_map(name)\n")
rep('\tspace_material.set_shader_parameter("stars_on", 1.0 if stars_on else 0.0)\n',
    '\tspace_material.set_shader_parameter("stars_on", 1.0 if stars_on else 0.0)\n\tMapBg.update(self, space_material)\n')
open(p + ".arkaplan_yedek", "wb").write(raw.encode("utf-8"))
out = s.replace("\n", "\r\n") if crlf else s
open(p, "wb").write(out.encode("utf-8"))
print("Tamam: main.gd guncellendi (yedek: main.gd.arkaplan_yedek)")
