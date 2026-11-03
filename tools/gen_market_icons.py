# NOVAGATE market ikonlari - tamamen prosedurel uretici (harici gorsel kullanmaz).
# Kullanim (proje kokunden):  python3 tools/gen_market_icons.py
# Gerekenler: numpy, scipy, opencv-python, Pillow
# Cikti: assets/items/*.png ve assets/ui/*.png (256x256, seffaf arka plan)
import os, sys
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
root = os.path.abspath(os.path.join(here, '..'))
import icons_weapons, icons_gens, icons_misc

items = os.path.join(root, 'assets', 'items')
ui = os.path.join(root, 'assets', 'ui')
icons_weapons.build(items)
icons_gens.build(items)
icons_misc.build(items, ui, os.path.join(root, 'drone_forms.gd'))
print('Tamam ->', items, '|', ui)
