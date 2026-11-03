# main.gd yamasi: 3D droid modelinin KENDI malzemelerini (celik + parlayan aksan) koru.
# Kullanim (proje kokunden):  python3 tools/patch_main_drone.py [main.gd yolu]
# - Yedek alir (main.gd.bak), tekrar calistirilirsa bir sey yapmaz.
# - Eski davranisa donmek icin: DRONE_KEEP_MODEL_MATERIALS := false
import os, re, shutil, sys

here = os.path.dirname(os.path.abspath(__file__))
path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, '..', 'main.gd')
raw = open(path, 'rb').read().decode('utf-8')
nl = '\r\n' if '\r\n' in raw else '\n'
src = raw.replace('\r\n', '\n')

if 'DRONE_KEEP_MODEL_MATERIALS' in src:
    print('Yama zaten uygulanmis.'); sys.exit(0)

a = 'const DRONE_MODEL_SIZE := 2.1'
i = src.find(a)
if i < 0:
    sys.exit('HATA: DRONE_MODEL_SIZE satiri bulunamadi (main.gd farkli olabilir).')
j = src.find('\n', i)
src = src[:j + 1] + 'const DRONE_KEEP_MODEL_MATERIALS := true   # true: modelin kendi malzemelerini koru (yeni droidler)\n' + src[j + 1:]

old = '\t\tfor s in mi.mesh.get_surface_count():\n\t\t\tmi.set_surface_override_material(s, mat)\n'
new = '\t\tif not DRONE_KEEP_MODEL_MATERIALS:\n\t\t\tfor s in mi.mesh.get_surface_count():\n\t\t\t\tmi.set_surface_override_material(s, mat)\n'
if src.count(old) != 1:
    sys.exit('HATA: set_surface_override_material blogu bulunamadi / birden fazla (main.gd farkli olabilir).')
src = src.replace(old, new)

shutil.copyfile(path, path + '.bak')
open(path, 'wb').write(src.replace('\n', nl).encode('utf-8'))
print('Yama uygulandi ->', os.path.abspath(path), '(yedek: main.gd.bak)')
