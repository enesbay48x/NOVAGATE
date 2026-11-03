# NOVAGATE ozgun lazer sprite uretici. Tamamen prosedurel: hicbir harici gorsel kullanilmaz.
# Cikti: RGBA PNG, sivri uc SOLDA (oyundaki yon kurali), additive blend icin siyah=seffaf.
import numpy as np
from PIL import Image
import os, sys

SS = 4  # supersample

def grid(w, h):
    xs = (np.arange(w * SS) + 0.5) / (w * SS)          # u: 0 (uc) .. 1 (kuyruk)
    ys = ((np.arange(h * SS) + 0.5) / (h * SS)) * 2 - 1  # v: -1..1
    return np.meshgrid(xs, ys)

def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)

def finish(r, g, b, a, w, h, path):
    img = np.stack([r, g, b, a], -1)
    img = np.clip(img, 0, 1)
    im = Image.fromarray((img * 255).astype(np.uint8), "RGBA")
    im = im.resize((w, h), Image.LANCZOS)
    arr = np.array(im).astype(np.float32) / 255.0
    # kenarlari tamamen sifirla (yanal sizinti olmasin)
    arr[0, :, :] = 0; arr[-1, :, :] = 0; arr[:, -1, :] = 0
    Image.fromarray((arr * 255).astype(np.uint8), "RGBA").save(path)

def bolt(path, w, h, glow, mid, core=(1, 1, 1), head=0.16, width=1.0, tail=0.9,
         bands=0.0, band_f=18.0, twin=False, zig=0.0, zig_f=9.0, hot=1.4, flare=0.0):
    U, V = grid(w, h)
    # yari genislik profili: sivri uc (solda) -> govde -> uzun kuyruk solmasi
    head_p = np.power(smooth(0.0, head, U), 0.75)
    tail_p = 1.0 - smooth(1.0 - tail, 1.0, U) * 0.92
    hw = np.clip(width * head_p * tail_p, 0.001, None)
    vv = V.copy()
    if zig > 0:
        vv = V + zig * np.sin(U * zig_f * np.pi * 2 + np.sin(U * 31.0) * 1.5) * smooth(0.05, 0.3, U)
    d = np.abs(vv) / hw
    along = (1.0 - smooth(0.0, 1.0, U) * 0.78) * (1.0 - smooth(0.7, 1.0, U))   # kuyruga dogru sonme
    halo = np.exp(-(d * 1.15) ** 2) * along * 0.85
    body = np.exp(-(d * 2.6) ** 2) * along
    c = np.exp(-(d * 6.2) ** 2) * (1.0 - smooth(0.0, 1.0, U) * 0.55)
    if twin:
        c = (np.exp(-((np.abs(vv) - 0.24 * hw) / (0.07 * hw + 1e-3)) ** 2)) * along * 1.1
    if bands > 0:
        pulse = 0.5 + 0.5 * np.sin(U * band_f * np.pi * 2)
        body = body * (1.0 - bands + bands * pulse)
    # sivri uc parlamasi
    tip = np.exp(-((U - head * 0.55) / (head * 0.45)) ** 2) * np.exp(-(d * 3.2) ** 2) * hot
    # burun fisek parlamasi (isik hale)
    fl = np.exp(-((U - 0.07) / 0.05) ** 2) * np.exp(-(np.abs(V) / 0.4) ** 2) * flare * smooth(0.0, 0.04, U)
    I_g = halo
    I_m = body
    I_c = np.clip(c + tip + fl, 0, 1.6)
    r = glow[0] * I_g + mid[0] * I_m + core[0] * I_c
    g = glow[1] * I_g + mid[1] * I_m + core[1] * I_c
    b = glow[2] * I_g + mid[2] * I_m + core[2] * I_c
    a = np.clip(I_g * 0.9 + I_m + I_c, 0, 1)
    finish(r, g, b, a, w, h, path)

def orb(path, w, h, glow, mid, core, ring=0.0, spikes=0, stretch=1.0):
    X = (np.arange(w * SS) + 0.5) / (w * SS) * 2 - 1
    Y = (np.arange(h * SS) + 0.5) / (h * SS) * 2 - 1
    X, Y = np.meshgrid(X, Y)
    R = np.sqrt((X * stretch) ** 2 + Y ** 2)
    ang = np.arctan2(Y, X * stretch)
    halo = np.exp(-(R / 0.62) ** 2) * 0.8
    body = np.exp(-(R / 0.34) ** 2)
    c = np.exp(-(R / 0.15) ** 2) * 1.3
    if ring > 0:
        halo = halo + ring * np.exp(-((R - 0.7) / 0.07) ** 2)
    if spikes:
        sp = np.abs(np.cos(ang * spikes / 2.0)) ** 14
        halo = halo + 0.7 * sp * np.exp(-(R / 0.8) ** 2)
    r = glow[0] * halo + mid[0] * body + core[0] * c
    g = glow[1] * halo + mid[1] * body + core[1] * c
    b = glow[2] * halo + mid[2] * body + core[2] * c
    a = np.clip(halo + body + c, 0, 1)
    finish(r, g, b, a, w, h, path)

def lance(path, w, h, glow, mid, core, facets=6):
    """Agir kristal mizrak (Kristallon vb.): elmas bas + parlak eksen."""
    U, V = grid(w, h)
    head = 0.22
    hp = np.where(U < head, np.power(U / head, 0.9), 1.0)
    tp = 1.0 - smooth(0.55, 1.0, U) * 0.95
    hw = np.clip(hp * tp, 0.001, None)
    d = np.abs(V) / hw
    along = (1.0 - smooth(0.0, 1.0, U) * 0.65) * (1.0 - smooth(0.8, 1.0, U))
    facet = 0.65 + 0.35 * np.abs(np.sin(U * facets * np.pi))
    halo = np.exp(-(d * 1.1) ** 2) * along * 0.8
    body = np.exp(-(d * 2.1) ** 2) * along * facet
    c = np.exp(-(d * 5.5) ** 2) * (1 - smooth(0, 1, U) * 0.5)
    tip = np.exp(-((U - 0.1) / 0.07) ** 2) * np.exp(-(d * 2.5) ** 2) * 1.5
    ci = np.clip(c + tip, 0, 1.6)
    r = glow[0] * halo + mid[0] * body + core[0] * ci
    g = glow[1] * halo + mid[1] * body + core[1] * ci
    b = glow[2] * halo + mid[2] * body + core[2] * ci
    a = np.clip(halo + body + ci, 0, 1)
    finish(r, g, b, a, w, h, path)

OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
os.makedirs(OUT, exist_ok=True)
P = lambda n: os.path.join(OUT, n + ".png")
W, H = 156, 40   # oyuncu lazerleri 2x cozunurluk (tabloda 78x20 ile ayni oran)

# ---- oyuncu muhimmatlari (her biri farkli bicim) ----
bolt(P("nv_x1"),  W, H, glow=(0.95, 0.12, 0.08), mid=(1.0, 0.38, 0.2),  core=(1.0, 0.92, 0.8),  head=0.14, width=0.55, tail=0.85, hot=1.6)
bolt(P("nv_x2"),  W, H, glow=(0.12, 0.45, 1.0),  mid=(0.35, 0.7, 1.0),  core=(0.9, 0.97, 1.0),  head=0.20, width=0.8,  tail=0.8,  flare=0.5)
bolt(P("nv_x3"),  W, H, glow=(0.1, 0.9, 0.35),   mid=(0.3, 1.0, 0.5),   core=(0.9, 1.0, 0.92),  head=0.16, width=0.85, tail=0.85, twin=True)
bolt(P("nv_x4"),  W, H, glow=(0.55, 0.7, 1.0),   mid=(0.85, 0.92, 1.0), core=(1.0, 1.0, 1.0),   head=0.22, width=1.0,  tail=0.75, bands=0.35, band_f=7.0, flare=0.7)
bolt(P("nv_sab"), W, H, glow=(0.1, 0.8, 0.85),   mid=(0.4, 0.95, 0.95), core=(0.9, 1.0, 1.0),   head=0.18, width=0.8,  tail=0.8,  zig=0.12, zig_f=2.5)
bolt(P("nv_rsb"), 156, 36, glow=(1.0, 0.55, 0.05), mid=(1.0, 0.78, 0.25), core=(1.0, 0.97, 0.85), head=0.18, width=1.0, tail=0.8, zig=0.2, zig_f=4.0, flare=0.8)

# ---- NPC atislari (aileye gore) ----
bolt(P("nv_streuner"),  132, 40, glow=(0.75, 0.2, 1.0), mid=(0.9, 0.5, 1.0), core=(1.0, 0.92, 1.0), head=0.2, width=0.7, tail=0.8)
bolt(P("nv_lordakia"),  194, 74, glow=(0.8, 1.0, 0.1), mid=(0.95, 1.0, 0.4), core=(1.0, 1.0, 0.9),  head=0.3, width=0.9, tail=0.7, flare=0.6)
orb(P("nv_devolarium"), 96, 96, glow=(1.0, 0.45, 0.1), mid=(1.0, 0.7, 0.3), core=(1.0, 0.97, 0.85), ring=0.5)
orb(P("nv_sibelon"),    96, 96, glow=(0.15, 0.85, 1.0), mid=(0.5, 0.95, 1.0), core=(1.0, 1.0, 1.0), spikes=8)
orb(P("nv_sibelonit"),  96, 96, glow=(0.95, 0.2, 0.55), mid=(1.0, 0.55, 0.75), core=(1.0, 0.95, 0.98), spikes=6)
bolt(P("nv_protegit"),  46, 14, glow=(0.6, 0.3, 1.0), mid=(0.8, 0.6, 1.0), core=(1, 1, 1), head=0.3, width=0.9, tail=0.7)
bolt(P("nv_kristallin"), 160, 32, glow=(0.3, 0.55, 1.0), mid=(0.6, 0.8, 1.0), core=(1, 1, 1), head=0.2, width=0.85, tail=0.8, bands=0.2, band_f=5.0)
lance(P("nv_kristallon"), 300, 48, glow=(0.2, 0.5, 1.0), mid=(0.55, 0.78, 1.0), core=(1.0, 1.0, 1.0))
lance(P("nv_cubikon"),    300, 48, glow=(1.0, 0.25, 0.2), mid=(1.0, 0.55, 0.4), core=(1.0, 0.95, 0.9))
print("ok", len(os.listdir(OUT)))
