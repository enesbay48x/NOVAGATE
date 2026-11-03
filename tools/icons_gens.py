from iconlib import *
from icons_weapons import metal_plate, metal_cyl, energy_slot, STEEL_T, STEEL_B, DARK_T, DARK_B
import math


def polar_poly(cx, cy, r0, r1, a0, w0, w1, twist, n=14):
    """Egri kanat/kanatcik: kok (r0) -> uc (r1)."""
    L, R = [], []
    for i in range(n + 1):
        t = i / n
        r = lerp(r0, r1, t)
        a = a0 + twist * t
        hw = lerp(w0, w1, t)
        L.append((cx + r * math.cos(a - hw), cy + r * math.sin(a - hw)))
        R.append((cx + r * math.cos(a + hw), cy + r * math.sin(a + hw)))
    return L + R[::-1]


def radial_fill(cx, cy, r, c_in, c_out, power=1.0, alpha_out=1.0):
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / r
    t = np.clip(d, 0, 1) ** power
    rgb = lerp(np.array(c_in, np.float32)[None, None, :], np.array(c_out, np.float32)[None, None, :], t[..., None])
    return rgb


SPEED = {
    'g3n-1010': dict(c='#ffbf2f', blades=4, ring=('#9aa6b8', '#394152'), tw=0.55, accent=None, hot=(1, .95, .75)),
    'g3n-2010': dict(c='#ffa21f', blades=5, ring=('#a3aec0', '#3a4354'), tw=0.62, accent='#ffa21f', hot=(1, .93, .7)),
    'g3n-3210': dict(c='#ff8a1c', blades=6, ring=('#a9b4c6', '#3b4558'), tw=0.7, accent='#ff8a1c', hot=(1, .9, .65)),
    'g3n-3310': dict(c='#ff6a1a', blades=7, ring=('#b0bbcd', '#3d475a'), tw=0.78, accent='#ff6a1a', hot=(1, .88, .62)),
    'g3n-6900': dict(c='#ff3b2c', blades=8, ring=('#8e97a8', '#2a303c'), tw=0.85, accent='#ff3b2c', hot=(1, .82, .7)),
    'g3n-7900': dict(c='#3fe7ff', blades=10, ring=('#ffd978', '#9a6a14'), tw=0.95, accent='#3fe7ff', hot=(.9, 1, 1)),
}


def speed_gen(gid):
    P = SPEED[gid]
    c = col(P['c'])
    cv = canvas()
    cx = cy = C
    R_OUT, R_IN = 318, 246
    outer = ring(cx, cy, R_OUT, R_IN)
    full = circle(cx, cy, R_OUT)
    cv = shadow(cv, full, 6, 14, 18, 0.55)
    # --- ic kuyu (koyu) + parlak enerji
    well = circle(cx, cy, R_IN + 2)
    wellc = radial_fill(cx, cy, R_IN, (0.10, 0.11, 0.15), (0.015, 0.02, 0.03), 0.8)
    cv = over(cv, np.dstack([wellc * well[..., None], well]))
    # kuyunun icinden gelen sicak isik
    glowmask = circle(cx, cy, 120)
    cv = add(cv, glow_layer(glowmask, c, 90, 1.1, 0.5))
    # --- kanatlar
    nb = P['blades']
    blades = blank()
    hubs = []
    for i in range(nb):
        a = i * (2 * math.pi / nb)
        pts = polar_poly(cx, cy, 70, R_IN - 14, a, min(0.20, 0.78 / nb), min(0.34, 1.25 / nb), P['tw'])
        blades = np.maximum(blades, poly(pts))
    bl_shadow = np.dstack([np.zeros((S, S, 3), np.float32), blur(blades, 10) * 0.6])
    cv = over(cv, bl_shadow * np.dstack([np.ones((S, S, 3)), np.ones((S, S, 1))]).astype(np.float32))
    bcv = lit(blades, height_bevel(blades, 14, 2), col('#c9d2e2'), col('#3a4458'), spec=0.7, shin=24,
              amb=0.22, dif=1.0, metal=0.7, env=DARKMETAL, k=1.0, outline=2.5)
    cv = over(cv, bcv)
    # kanat uclarinda sicak isik cizgisi
    tip = ring(cx, cy, R_IN - 8, R_IN - 26) * blades
    cv = add(cv, glow_layer(tip, c, 14, 0.8))
    # --- merkez goбek
    hub = circle(cx, cy, 74)
    cv = over(cv, metal_plate(hub, col('#bcc6d8'), col('#3a4458'), 26, metal=0.7))
    core = circle(cx, cy, 44)
    cv = energy_slot(cv, core, c, P['hot'], 1.2)
    cv = add(cv, glow_layer(circle(cx, cy, 22), P['hot'], 14, 1.0, 0.9))
    # --- dis halka
    t, b = col(P['ring'][0]), col(P['ring'][1])
    cv = over(cv, metal_plate(outer, t, b, 34, spec=0.8, metal=0.75))
    cv = over(cv, rim_highlight(outer, 0.35))
    # ic kenar enerji halkasi
    if P['accent']:
        ac = col(P['accent'])
        e = ring(cx, cy, R_IN + 26, R_IN + 18)
        cv = add(cv, glow_layer(e, ac, 10, 0.9))
        cv = over(cv, flat(e, np.clip(ac * 0.7 + 0.3, 0, 1), 0.95))
    # vidalar
    for i in range(8):
        a = i * math.pi / 4 + math.pi / 8
        sx, sy = cx + (R_OUT - 36) * math.cos(a), cy + (R_OUT - 36) * math.sin(a)
        sc = circle(sx, sy, 13)
        cv = over(cv, metal_plate(sc, col('#dfe6f3'), col('#4a566c'), 7, metal=0.6))
        cv = over(cv, flat(circle(sx, sy, 4.5), (0.08, 0.1, 0.14), 0.9))
    # ust seviyelerde dis zirh parcalari
    idx = list(SPEED).index(gid)
    if idx >= 2:
        for i in range(4):
            a = i * math.pi / 2 + math.pi / 4
            arc = ring(cx, cy, R_OUT + 2, R_OUT - 26)
            wedge = poly([(cx, cy),
                          (cx + 500 * math.cos(a - 0.22), cy + 500 * math.sin(a - 0.22)),
                          (cx + 500 * math.cos(a + 0.22), cy + 500 * math.sin(a + 0.22))])
            seg = arc * wedge
            sc = ring(cx, cy, R_OUT + 2, R_OUT - 26) * wedge
            cv = over(cv, flat(sc, (0.05, 0.06, 0.09), 0.35))
            if P['accent']:
                mark = circle(cx + (R_OUT - 13) * math.cos(a), cy + (R_OUT - 13) * math.sin(a), 8)
                cv = add(cv, glow_layer(mark, col(P['accent']), 8, 0.9))
                cv = over(cv, flat(mark, np.clip(col(P['accent']) * 0.6 + 0.4, 0, 1), 1))
    return fit(cv, 0.9)


# ------------------------------------------------------------------ kalkan jeneratorleri
SHIELD = {
    'sg3n-a01': dict(c='#37e58a', pips=1, frame=('#a6b3c6', '#364051'), wings=0, hot=(.85, 1, .92)),
    'sg3n-a02': dict(c='#2fd0ff', pips=2, frame=('#a9b8cc', '#364254'), wings=0, hot=(.85, .98, 1)),
    'sg3n-a03': dict(c='#3a86ff', pips=3, frame=('#adbcd2', '#374257'), wings=0, hot=(.88, .93, 1)),
    'sg3n-b01': dict(c='#a15cff', pips=4, frame=('#b4a8d6', '#3b3358'), wings=1, hot=(.95, .9, 1)),
    'sg3n-b02': dict(c='#ffd23f', pips=5, frame=('#ffe08a', '#8c5f10'), wings=2, hot=(1, .98, .85)),
}


def shield_shape(cx, top, mid, bot, hw, dip=26, corner=14):
    pts = []
    n = 40
    # ust kenar (hafif girintili)
    for i in range(n + 1):
        t = i / n
        x = cx - hw + 2 * hw * t
        u = (t - 0.5) * 2
        y = top + dip * (1 - u * u) * 0 + dip * (1 - abs(u)) * 0.0 + (dip * (1 - u * u))
        pts.append((x, y))
    # sag kenar asagi
    for i in range(1, n + 1):
        t = i / n
        if t < 0.5:
            y = lerp(top + dip * 0.0, mid, t / 0.5)
            x = cx + hw
        else:
            u = (t - 0.5) / 0.5
            y = lerp(mid, bot, u)
            x = cx + hw * (1 - u ** 1.9) ** 0.62
        pts.append((x, y))
    right = pts[n + 1:]
    left = [(2 * cx - x, y) for (x, y) in right[::-1]]
    top_edge = pts[:n + 1]
    return top_edge + right + left


def shield_gen(gid):
    P = SHIELD[gid]
    c = col(P['c'])
    cv = canvas()
    cx = C
    top, mid, bot, hw = 120, 400, 690, 235
    sh_pts = shield_shape(cx, top, mid, bot, hw)
    sh = poly(sh_pts)
    # kanatlar (b serisi)
    wing_layer = blank()
    if P['wings'] >= 1:
        for sgn in (-1, 1):
            w = poly([(cx + sgn * (hw - 10), 190), (cx + sgn * (hw + 95), 130), (cx + sgn * (hw + 88), 250),
                      (cx + sgn * (hw + 34), 330), (cx + sgn * (hw - 10), 330)])
            wing_layer = np.maximum(wing_layer, w)
    if P['wings'] >= 2:
        for sgn in (-1, 1):
            w = poly([(cx + sgn * (hw + 10), 345), (cx + sgn * (hw + 78), 335), (cx + sgn * (hw + 56), 430),
                      (cx + sgn * (hw - 5), 470)])
            wing_layer = np.maximum(wing_layer, w)
    everything = np.maximum(sh, wing_layer)
    cv = shadow(cv, everything, 6, 14, 16, 0.55)
    ft, fb = col(P['frame'][0]), col(P['frame'][1])
    if wing_layer.max() > 0:
        cv = over(cv, metal_plate(wing_layer, ft * 0.85, fb, 18, spec=0.7, metal=0.7))
        wing_edge = wing_layer
        cv = add(cv, glow_layer(ring_from_mask(wing_layer, 8, 14), c, 8, 0.0))
    # --- kalkan cerçevesi
    cv = over(cv, metal_plate(sh, ft, fb, 38, spec=0.9, metal=0.8))
    cv = over(cv, rim_highlight(sh, 0.4))
    # ic panel (koyu cam)
    d = ndi.distance_transform_edt(sh > 0.5).astype(np.float32)
    inner = np.clip((d - 40) / 1.6, 0, 1)
    wellc = radial_fill(cx, 360, 330, (0.10, 0.13, 0.2), (0.015, 0.02, 0.035), 0.9)
    cv = over(cv, np.dstack([wellc * inner[..., None], inner]))
    # ic kenar enerji cizgisi
    edge_ring = np.clip(1 - np.abs(d - 46) / 3.0, 0, 1) * sh
    cv = add(cv, glow_layer(edge_ring, c, 9, 0.9))
    cv = over(cv, flat(edge_ring, np.clip(c * 0.6 + 0.4, 0, 1), 0.9))
    # --- hex hucre dokusu
    hexcells = blank()
    ys0 = 150
    for row in range(-1, 9):
        for colm in range(-1, 8):
            hx = cx + (colm - 3) * 74 + (37 if row % 2 else 0)
            hy = ys0 + row * 64
            hp = [(hx + 33 * math.cos(math.pi / 3 * k + math.pi / 6), hy + 33 * math.sin(math.pi / 3 * k + math.pi / 6)) for k in range(6)]
            hexcells = np.maximum(hexcells, np.clip(poly(hp) - blur(poly(hp), 0) * 0 - erode(poly(hp), 3), 0, 1))
    hexcells *= inner
    hexcells *= radial_alpha(cx, 380, 330, 0.18)
    cv = add(cv, np.dstack([c[None, None, :] * hexcells[..., None] * 0.9, hexcells * 0.6]))
    # --- merkez altigen cekirdek
    hx_pts = [(cx + 128 * math.cos(math.pi / 3 * k + math.pi / 6), 360 + 128 * math.sin(math.pi / 3 * k + math.pi / 6)) for k in range(6)]
    hexm = poly(hx_pts)
    hex_in = poly([(cx + 92 * math.cos(math.pi / 3 * k + math.pi / 6), 360 + 92 * math.sin(math.pi / 3 * k + math.pi / 6)) for k in range(6)])
    hexring = np.clip(hexm - hex_in, 0, 1)
    cv = add(cv, glow_layer(hexm, c, 46, 1.0, 0.5))
    cv = over(cv, metal_plate(hexring, ft, fb, 14, spec=0.8, metal=0.75))
    cv = energy_slot(cv, hex_in, c, P['hot'], 1.2)
    cv = add(cv, glow_layer(circle(cx, 360, 24), P['hot'], 16, 1.0, 0.9))
    # --- seviye isaretleri (pips)
    n = P['pips']
    gap = 44
    x0 = cx - (n - 1) * gap / 2
    for i in range(n):
        pm = poly([(x0 + i * gap, 520), (x0 + i * gap + 17, 536), (x0 + i * gap, 552), (x0 + i * gap - 17, 536)])
        cv = add(cv, glow_layer(pm, c, 10, 0.9))
        cv = over(cv, flat(pm, np.clip(c * 0.55 + 0.45, 0, 1), 1))
        cv = over(cv, flat(poly([(x0 + i * gap, 526), (x0 + i * gap + 7, 536), (x0 + i * gap, 546), (x0 + i * gap - 7, 536)]), P['hot'], 1))
    return fit(cv, 0.9)


def erode(m, px):
    d = ndi.distance_transform_edt(m > 0.5).astype(np.float32)
    return np.clip((d - px) / 1.2, 0, 1)


def ring_from_mask(m, a, b):
    d = ndi.distance_transform_edt(m > 0.5).astype(np.float32)
    return np.clip(1 - np.abs(d - (a + b) / 2) / ((b - a) / 2), 0, 1) * m


def radial_alpha(cx, cy, r, k):
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / r
    return np.clip(1 - d, 0, 1) ** 0.8 * (1 - k) + k * 0.2


def build(outdir):
    import os
    os.makedirs(outdir, exist_ok=True)
    for g in SPEED:
        finish(speed_gen(g), os.path.join(outdir, 'generator_%s.png' % g))
    for g in SHIELD:
        finish(shield_gen(g), os.path.join(outdir, 'generator_%s.png' % g))


if __name__ == '__main__':
    build('/home/claude/out_test')
