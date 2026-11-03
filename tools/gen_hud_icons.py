# HUD (alt cubuk) ikonlari: marketteki ikonlarla AYNI gorseller, HUD'un bekledigi dosya adlariyla.
# Kullanim (proje kokunden, once gen_market_icons.py calismis olmali):  python3 tools/gen_hud_icons.py
import os, numpy as np
from PIL import Image

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.abspath(os.path.join(here, '..'))
items = os.path.join(root, 'assets', 'items')
ui = os.path.join(root, 'assets', 'ui')
out = os.path.join(root, 'assets', 'hud', 'items')
os.makedirs(out, exist_ok=True)


def shrink(path, size, pad=0.0):
    im = Image.open(path).convert('RGBa')           # premultiplied: kenarlarda halo olmasin
    if pad > 0:
        w = im.width
        canvas = Image.new('RGBa', (w, w), (0, 0, 0, 0))
        k = 1.0 - 2 * pad
        s = int(w * k)
        canvas.paste(im.resize((s, s), Image.LANCZOS), ((w - s) // 2, (w - s) // 2))
        im = canvas
    return im.resize((size, size), Image.LANCZOS).convert('RGBA')


def hover(im):
    a = np.asarray(im).astype(np.float32) / 255.0
    rgb = a[..., :3]
    rgb = np.clip(rgb * 1.22 + 0.05 * a[..., 3:4], 0, 1)
    return Image.fromarray((np.dstack([rgb, a[..., 3]]) * 255 + 0.5).astype(np.uint8), 'RGBA')


# cephane (hud_do.gd: LASER_IDS -> LASER_ICONS)
AMMO = {'x1': 'lcb-10', 'x2': 'mcb-25', 'x3': 'mcb-50', 'x4': 'ucb-100', 'sab': 'sab-50', 'rsb': 'rsb-75'}
for k, v in AMMO.items():
    shrink(os.path.join(ui, 'ammo_%s.png' % k), 64).save(os.path.join(out, 'ammunition_laser_%s.png' % v))
shrink(os.path.join(ui, 'rocket_r310.png'), 64).save(os.path.join(out, 'ammunition_rocket_r-310.png'))

# droid dizilimleri (drone_forms.gd ICONS)
FORMS = {'default': 'std', 'f-01-tu': 'tu', 'f-02-ar': 'ar', 'f-03-la': 'la', 'f-04-st': 'st', 'f-05-pi': 'pi',
         'f-06-da': 'da', 'f-07-di': 'di', 'f-08-ch': 'ch', 'f-09-mo': 'mo', 'f-10-cr': 'cr', 'f-11-he': 'he', 'f-12-ba': 'ba'}
for k, v in FORMS.items():
    shrink(os.path.join(items, 'form_%s.png' % v), 64).save(os.path.join(out, 'drone_formation_%s.png' % k))

# kategori dugmeleri (orta sira): lazer / roket / droid dizilimleri
CATS = {'lasers': os.path.join(items, 'weapon_lf3.png'),
        'rockets': os.path.join(ui, 'rocket_r310.png'),
        'drone_formations': os.path.join(items, 'drone_flax.png')}
for k, src in CATS.items():
    n = shrink(src, 80, pad=0.05 if k == 'lasers' else 0.12)
    n.save(os.path.join(out, '%s_normal.png' % k))
    hover(n).save(os.path.join(out, '%s_hover.png' % k))
print('HUD ikonlari ->', out)
