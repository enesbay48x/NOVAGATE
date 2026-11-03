# NOVAGATE 3D droid modelleri (Flax + Iris): markettaki ikonlarla ayni tasarim.
# Kullanim (proje kokunden):  python3 tools/gen_drone_models.py   -> models/drone_flax_6.glb, models/drone_iris_6.glb
# Burun -Z'ye bakar, ust yuz +Y. Cok malzemeli (celik / koyu / parlayan aksan) - main.gd yamasi bunlari korur.
import os, sys, math
import numpy as np
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
from glblib import Mesh, rx, ry, rz


def mirror(pts):
    return [(-x, z) for (x, z) in pts][::-1]


def flax():
    M = Mesh()
    steel = M.mat('flax_steel', (0.72, 0.76, 0.84), 0.35, 0.40)
    dark = M.mat('flax_dark', (0.17, 0.19, 0.24), 0.45, 0.50)
    orange = M.mat('flax_orange', (1.0, 0.42, 0.08), 0.0, 0.5, emit=(1.0, 0.45, 0.08), emit_k=2.4)
    hot = M.mat('flax_hot', (1.0, 0.85, 0.55), 0.0, 0.4, emit=(1.0, 0.82, 0.45), emit_k=3.4)

    # --- govde (konveks altigen-benzeri), alt/ust pah
    hull = [(0.0, -0.88), (0.25, -0.52), (0.30, 0.27), (0.18, 0.78), (-0.18, 0.78), (-0.30, 0.27), (-0.25, -0.52)]
    M.prism(steel, hull, -0.13, 0.17, inset=0.62, mid=(0.06, 1.0))
    # orta koyu seritler (govde uzerinde)
    for z in (0.12, 0.38):
        M.box(dark, (0.46, 0.012, 0.045), t=(0, 0.19 - 0.12 * (z - 0.12), z))

    # --- kanatlar (ince, suprulmus) + turuncu seritler
    for sg in (-1, 1):
        wing = [(0.22 * sg, -0.23), (1.07 * sg, 0.27), (1.04 * sg, 0.52), (0.77 * sg, 0.59), (0.22 * sg, 0.45)]
        if sg < 0:
            wing = wing[::-1]
        M.prism(dark, wing, -0.045, 0.045, inset=0.92, mid=(0.03, 1.0))
        stripe = [(0.40 * sg, 0.16), (0.96 * sg, 0.34), (0.94 * sg, 0.43), (0.40 * sg, 0.30)]
        if sg < 0:
            stripe = stripe[::-1]
        M.prism(orange, stripe, 0.048, 0.062, inset=1.0)
        # kanat ucu kucuk isik
        M.sphere(hot, 0.035, 10, 6, t=(1.0 * sg, 0.05, 0.5))

    # --- yan silah kapsulleri
    for sg in (-1, 1):
        x = 0.55 * sg
        M.cylz(steel, 0.115, -0.70, 0.30, 20, x=x, y=0.0)
        M.cylz(dark, 0.125, -0.12, -0.04, 20, x=x, y=0.0)
        M.cylz(dark, 0.125, 0.10, 0.18, 20, x=x, y=0.0)
        M.cylz(dark, 0.092, -0.80, -0.70, 16, x=x, y=0.0)         # namlu agzi
        M.sphere(hot, 0.062, 14, 8, t=(x, 0.0, -0.81))            # parlayan uc
        M.cylz(orange, 0.1, 0.30, 0.34, 16, x=x, y=0.0)           # arka itici isik
        # kapsul - govde baglanti plakasi
        M.box(dark, (0.20, 0.07, 0.26), t=(0.40 * sg, 0.0, -0.05))

    # --- kokpit / sensor (turuncu cam)
    M.sphere(orange, 0.5, 20, 10, t=(0, 0.14, -0.20), scale=(0.28, 0.17, 0.56), hemi=True)
    M.sphere(hot, 0.5, 14, 8, t=(0, 0.16, -0.24), scale=(0.12, 0.14, 0.28), hemi=True)

    # --- arka motor
    M.cylz(dark, 0.15, 0.64, 0.88, 20, x=0, y=0.0)
    M.cylz(orange, 0.115, 0.88, 0.905, 18, x=0, y=0.0)
    M.sphere(hot, 0.07, 12, 8, t=(0, 0, 0.905))
    return M


def iris():
    M = Mesh()
    steel = M.mat('iris_steel', (0.72, 0.76, 0.85), 0.35, 0.40)
    dark = M.mat('iris_dark', (0.14, 0.16, 0.21), 0.45, 0.50)
    cyan = M.mat('iris_cyan', (0.15, 0.80, 1.0), 0.0, 0.5, emit=(0.2, 0.85, 1.0), emit_k=2.6)
    core = M.mat('iris_core', (0.85, 1.0, 1.0), 0.0, 0.4, emit=(0.85, 1.0, 1.0), emit_k=3.8)

    # --- dis halka (pahli profil)
    ring_prof = [(0.74, -0.12), (0.94, -0.12), (1.04, -0.06), (1.04, 0.06), (0.94, 0.13), (0.74, 0.13), (0.74, -0.12)]
    M.lathe(steel, ring_prof, 48)
    # halka ust yuzunde ince koyu oluk + ic enerji cizgisi
    M.lathe(dark, [(0.84, 0.131), (0.90, 0.131), (0.90, 0.136), (0.84, 0.136), (0.84, 0.131)], 48)
    M.lathe(cyan, [(0.745, 0.10), (0.775, 0.10), (0.775, 0.108), (0.745, 0.108), (0.745, 0.10)], 48)
    # --- ic kuyu
    M.lathe(dark, [(0.0, -0.03), (0.75, -0.03), (0.75, -0.02), (0.0, -0.02)], 40)
    # --- diyafram kanatcıkları (8 adet, ust uste binen)
    nb = 8
    for i in range(nb):
        a = i * 2 * math.pi / nb
        r0, r1 = 0.26, 0.76
        pts = [(r0 * math.cos(a - 0.13), r0 * math.sin(a - 0.13)),
               (r0 * math.cos(a + 0.13), r0 * math.sin(a + 0.13)),
               (r1 * math.cos(a + 0.55 - 0.44), r1 * math.sin(a + 0.55 - 0.44)),
               (r1 * math.cos(a + 0.55 + 0.44), r1 * math.sin(a + 0.55 + 0.44))]
        # konveks sirala (aci ile)
        c = np.mean(pts, 0)
        pts.sort(key=lambda p: math.atan2(p[1] - c[1], p[0] - c[0]))
        y0 = 0.0 + 0.018 * (i % 2)
        M.prism(steel, pts, y0, y0 + 0.035, inset=0.96)
        # kanat kenarinda ince cyan cizgi
    # --- merkez parlak goz
    M.lathe(cyan, [(0.0, -0.01), (0.27, -0.01), (0.27, 0.012), (0.0, 0.012)], 36)
    M.sphere(core, 0.20, 24, 10, t=(0, 0.01, 0), scale=(1, 0.75, 1), hemi=True)
    # --- yan itici kapsuller
    for sg in (-1, 1):
        x = 1.12 * sg
        M.box(steel, (0.26, 0.20, 0.78), t=(x, 0.0, 0.04))
        M.box(dark, (0.275, 0.05, 0.50), t=(x, 0.0, 0.04))
        M.box(cyan, (0.18, 0.10, 0.05), t=(x, 0.0, 0.46))        # itici isigi
        M.box(dark, (0.30, 0.10, 0.20), t=(0.98 * sg - 0.0, 0.0, -0.05))
    # --- on mini toplar
    for sg in (-1, 1):
        x = 0.40 * sg
        M.cylz(steel, 0.075, -1.22, -0.78, 18, x=x, y=0.02)
        M.cylz(dark, 0.088, -0.95, -0.88, 18, x=x, y=0.02)
        M.cylz(dark, 0.085, -1.22, -1.17, 16, x=x, y=0.02)
        M.sphere(cyan, 0.05, 12, 8, t=(x, 0.02, -1.23))
        M.box(dark, (0.14, 0.07, 0.20), t=(x, 0.03, -0.80))
    # --- vidalar
    for i in range(8):
        a = i * math.pi / 4 + math.pi / 8
        M.cylz(dark, 0.0, 0, 0, 3, x=0, y=0) if False else None
        sx, sz = 0.89 * math.cos(a), 0.89 * math.sin(a)
        M.lathe(dark, [(0, 0.132), (0.032, 0.132), (0.032, 0.146), (0, 0.146)], 10, t=(sx, 0, sz))
    return M


def build(models_dir):
    os.makedirs(models_dir, exist_ok=True)
    flax().save(os.path.join(models_dir, 'drone_flax_6.glb'), 'drone_flax_6')
    iris().save(os.path.join(models_dir, 'drone_iris_6.glb'), 'drone_iris_6')


if __name__ == '__main__':
    root = os.path.abspath(os.path.join(here, '..'))
    build(os.path.join(root, 'models'))
    print('Tamam ->', os.path.join(root, 'models'))
