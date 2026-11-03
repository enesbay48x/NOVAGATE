#!/usr/bin/env python3
"""
NovaGate - iOS ikonlarini olusturur.

Godot "Invalid icon (icons/settings_58x58)" hatasi, export_presets.cfg'deki iOS ikon
dosyalarindan birinin yok/bozuk olmasindan gelir. Bu script, iOS bolumunde adi gecen
ve eksik/bozuk olan PNG'leri proje kokundeki icon.png'den uretir.

Kullanim (proje klasorunde, icon.png ve export_presets.cfg'nin oldugu yerde):
    python3 ios_ikon_olustur.py            # sadece eksik/bozuk olanlari uretir
    python3 ios_ikon_olustur.py --force    # hepsini yeniden uretir (mevcutlarin ustune yazar)
    python3 ios_ikon_olustur.py --kaynak yol/icon_1024.png   # 1024x1024 kaynak ikon ver

Gerekli: pip install pillow
Not: Apple, seffaflik (alfa kanali) olan ikonlari reddeder; ciktilar duz zemin uzerine
RGB olarak uretilir. 512 px kaynaktan 1024'e buyutme bulaniklik yapar, mumkunse 1024x1024 kaynak kullanin.
"""
import os
import re
import sys

from PIL import Image

args = sys.argv[1:]
force = "--force" in args
kaynak = "icon.png"
if "--kaynak" in args:
    kaynak = args[args.index("--kaynak") + 1]

if not os.path.exists("export_presets.cfg"):
    sys.exit("export_presets.cfg bulunamadi. Scripti proje klasorunde calistirin.")
if not os.path.exists(kaynak):
    sys.exit("Kaynak ikon bulunamadi: " + kaynak)

cfg = open("export_presets.cfg", encoding="utf-8").read()
# iOS preset bolumunun options kismi
m = re.search(r'platform="iOS"(.*?)(?=\n\[preset\.\d+\]\n|\Z)', cfg, re.S)
if not m:
    sys.exit("iOS preset'i bulunamadi.")
bolum = m.group(1)

src = Image.open(kaynak).convert("RGBA")
zemin = (8, 14, 28)  # koyu lacivert zemin (seffaf alani doldurur)


def uret(yol, boyut):
    os.makedirs(os.path.dirname(yol), exist_ok=True)
    img = src.resize((boyut, boyut), Image.LANCZOS)
    duz = Image.new("RGB", (boyut, boyut), zemin)
    duz.paste(img, mask=img.split()[3])
    duz.save(yol, "PNG")


def saglam(yol):
    try:
        with Image.open(yol) as im:
            im.load()
        return True
    except Exception:
        return False


olusan, atlanan = 0, 0
for ad, yol in re.findall(r'icons/([A-Za-z0-9_]+)="res://([^"]+)"', bolum):
    boyut = re.search(r"_(\d+)x\d+", ad)
    if not boyut:
        continue
    boyut = int(boyut.group(1))
    if not force and os.path.exists(yol) and saglam(yol):
        atlanan += 1
        continue
    uret(yol, boyut)
    olusan += 1
    print("uretildi: %s (%dx%d)" % (yol, boyut, boyut))

print("Bitti. Uretilen: %d, zaten saglam olan (atlanan): %d" % (olusan, atlanan))
if olusan:
    print("Godot'u acik tutuyorsaniz bir kez odak degistirin ya da projeyi yeniden tarayin, sonra tekrar disa aktarin.")
