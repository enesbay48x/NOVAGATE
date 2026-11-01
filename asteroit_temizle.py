# Kullanim:  main.gd'nin bulundugu klasorde   python asteroit_temizle.py
# Haritalara rastgele konan gri 3D kaya objelerini (asteroit) tamamen kapatir. Yedek: main.gd.asteroit_yedek
# Geri acmak icin main.gd'de  SPAWN_ASTEROIDS := false  satirini true yap.
import os, sys
p = "main.gd"
if not os.path.exists(p):
    sys.exit("main.gd bulunamadi: bu dosyayi main.gd ile ayni klasorde calistir.")
raw = open(p, "rb").read().decode("utf-8")
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")
if "SPAWN_ASTEROIDS" in s:
    sys.exit("Zaten uygulanmis. Degisiklik yapilmadi.")
old1 = 'const MAP_TEX := "res://assets/maps/%s.jpg"\n'
old2 = "\tfor i in int(10.0 * size_mul):\n\t\tvar o := make_ship(\"asset-mmo-asteroid\""
if s.count(old1) != 1 or s.count(old2) != 1:
    sys.exit("Beklenen satirlar bulunamadi (main.gd degismis olabilir).")
s = s.replace(old1, old1 + "const SPAWN_ASTEROIDS := false   # gri 3D asteroit kayalari: false = haritalarda hic olmaz\n")
s = s.replace(old2, "\tfor i in (int(10.0 * size_mul) if SPAWN_ASTEROIDS else 0):\n\t\tvar o := make_ship(\"asset-mmo-asteroid\"")
open(p + ".asteroit_yedek", "wb").write(raw.encode("utf-8"))
open(p, "wb").write((s.replace("\n", "\r\n") if crlf else s).encode("utf-8"))
print("Tamam: asteroitler kapatildi (yedek: main.gd.asteroit_yedek)")
