from iconlib import *
from icons_weapons import metal_plate, metal_cyl, energy_slot, STEEL_T, STEEL_B, DARK_T, DARK_B
from icons_gens import polar_poly, radial_fill, erode, ring_from_mask
import math, os, re
from PIL import Image, ImageDraw, ImageFont


def text_mask(txt, cx, cy, size, bold=True):
    f = None
    for p in ('/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'):
        if os.path.exists(p):
            f = ImageFont.truetype(p, size)
            break
    im = Image.new('L', (S, S), 0)
    d = ImageDraw.Draw(im)
    bb = d.textbbox((0, 0), txt, font=f)
    d.text((cx - (bb[0] + bb[2]) / 2, cy - (bb[1] + bb[3]) / 2), txt, fill=255, font=f)
    return np.array(im, np.float32) / 255.0


# ------------------------------------------------------------------ DROIDLER
def drone_flax():
    c = col('#ff8a1c')
    hot = (1, .9, .65)
    cv = canvas()
    cx = C
    wings = blank()
    for sg in (-1, 1):
        wings = np.maximum(wings, poly([(cx + sg * 70, 330), (cx + sg * 300, 470), (cx + sg * 290, 540), (cx + sg * 215, 560),
                                        (cx + sg * 70, 520)]))
    hull = poly([(cx, 150), (cx + 70, 250), (cx + 84, 470), (cx + 50, 610), (cx - 50, 610), (cx - 84, 470), (cx - 70, 250)])
    pods = []
    for sg in (-1, 1):
        pods.append(rrect(cx + sg * 150 - 34, 190, cx + sg * 150 + 34, 470, 22))
    every = np.maximum(np.maximum(wings, hull), union(*pods))
    cv = shadow(cv, every, 8, 16, 16, 0.55)
    cv = over(cv, metal_plate(wings, col('#7c889d'), col('#272e3b'), 20, metal=0.65))
    # kanat panel cizgisi ve aksan
    for sg in (-1, 1):
        stripe = poly([(cx + sg * 110, 400), (cx + sg * 270, 480), (cx + sg * 262, 505), (cx + sg * 110, 440)])
        cv = add(cv, glow_layer(stripe, c, 6, 0.4))
        cv = over(cv, flat(stripe, c, 0.95))
    for m in pods:
        cv = over(cv, metal_cyl(m, 'y', col('#aeb9cc'), col('#2f3746'), spec=0.9))
    # namlu aglari
    for sg in (-1, 1):
        mz = rrect(cx + sg * 150 - 22, 160, cx + sg * 150 + 22, 215, 12)
        cv = over(cv, metal_cyl(mz, 'y', col('#cfd7e6'), col('#3a4354')))
        cv = add(cv, glow_layer(circle(cx + sg * 150, 162, 15), c, 22, 1.0, 0.7))
        cv = add(cv, glow_layer(circle(cx + sg * 150, 162, 6), hot, 8, 1.0, 0.9))
    # govde
    cv = over(cv, metal_plate(hull, col('#b3bed1'), col('#2b3341'), 34, spec=0.9, metal=0.75))
    cv = over(cv, rim_highlight(hull, 0.35))
    # kokpit / sensor
    cp = ellipse(cx, 330, 42, 78)
    cv = energy_slot(cv, cp, c, hot, 0.9)
    cv = over(cv, rim_highlight(cp, 0.3))
    # arka motor
    en = rrect(cx - 40, 590, cx + 40, 640, 14)
    cv = over(cv, metal_cyl(en, 'y', col('#8d99ab'), col('#2b3341')))
    cv = add(cv, glow_layer(rrect(cx - 28, 612, cx + 28, 650, 12), c, 28, 1.0, 0.6))
    # arka plaka detaylari
    cv = over(cv, panel_lines(hull, [('h', 420, 340, 428), ('h', 520, 330, 438)], (0, 0, 0), 0.5, 3))
    for yy in (450, 510):
        for sg in (-1, 1):
            cv = over(cv, flat(circle(cx + sg * 50, yy, 7), (0.07, 0.09, 0.12), 0.9))
    return fit(cv, 0.9)


def drone_iris():
    c = col('#37d5ff')
    hot = (.88, 1, 1)
    cv = canvas()
    cx = cy = C
    # yan itici modulleri
    pods = []
    for sg in (-1, 1):
        pods.append(rrect(cx + sg * 290 - 38, cy - 90, cx + sg * 290 + 38, cy + 120, 26))
    # on mini toplar
    guns = []
    for sg in (-1, 1):
        guns.append(rrect(cx + sg * 105 - 22, 70, cx + sg * 105 + 22, 210, 14))
    outer = circle(cx, cy, 262)
    every = np.maximum(np.maximum(outer, union(*pods)), union(*guns))
    cv = shadow(cv, every, 8, 16, 16, 0.55)
    for m in guns:
        cv = over(cv, metal_cyl(m, 'y', col('#c3cde0'), col('#2e3645'), spec=0.9))
    for sg in (-1, 1):
        cv = add(cv, glow_layer(circle(cx + sg * 105, 74, 13), c, 20, 1.0, 0.7))
        cv = add(cv, glow_layer(circle(cx + sg * 105, 74, 5), hot, 8, 1.0, 0.9))
    for m in pods:
        cv = over(cv, metal_plate(m, col('#8a97ac'), col('#2a3140'), 14, metal=0.7))
    for sg in (-1, 1):
        th = rrect(cx + sg * 290 - 22, cy + 100, cx + sg * 290 + 22, cy + 150, 10)
        cv = add(cv, glow_layer(th, c, 24, 1.0, 0.5))
        cv = over(cv, flat(th, np.clip(c * 0.5 + 0.5, 0, 1), 0.95))
    # dis halka
    rg = ring(cx, cy, 262, 196)
    cv = over(cv, metal_plate(rg, col('#bcc7da'), col('#2d3543'), 30, spec=0.9, metal=0.8))
    cv = over(cv, rim_highlight(rg, 0.4))
    # ic kuyu
    well = circle(cx, cy, 198)
    cv = over(cv, np.dstack([radial_fill(cx, cy, 198, (0.05, 0.12, 0.18), (0.01, 0.02, 0.03), 0.8) * well[..., None], well]))
    cv = add(cv, glow_layer(circle(cx, cy, 90), c, 70, 1.0, 0.6))
    # diyafram (iris) kanatcik
    nb = 8
    blades = blank()
    for i in range(nb):
        a = i * 2 * math.pi / nb
        pts = polar_poly(cx, cy, 78, 192, a, 0.10, 0.37, 0.95)
        blades = np.maximum(blades, poly(pts))
    bcv = lit(blades, height_bevel(blades, 12, 2), col('#aab6ca'), col('#2a3241'), spec=0.7, shin=24,
              amb=0.22, dif=1.0, metal=0.7, env=DARKMETAL, outline=2.5)
    cv = over(cv, bcv)
    # kanatlarin ortasindaki acik goz (parlak)
    pup = circle(cx, cy, 76)
    cv = energy_slot(cv, pup, c, hot, 1.3)
    cv = add(cv, glow_layer(circle(cx, cy, 30), hot, 18, 1.0, 1.0))
    # ic halka enerji cizgisi
    e = ring(cx, cy, 203, 193)
    cv = add(cv, glow_layer(e, c, 10, 0.9))
    cv = over(cv, flat(e, np.clip(c * 0.6 + 0.4, 0, 1), 0.95))
    # vidalar
    for i in range(8):
        a = i * math.pi / 4 + math.pi / 8
        sx, sy = cx + 232 * math.cos(a), cy + 232 * math.sin(a)
        cv = over(cv, metal_plate(circle(sx, sy, 11), col('#dfe6f3'), col('#4a566c'), 6, metal=0.6))
        cv = over(cv, flat(circle(sx, sy, 4), (0.08, 0.1, 0.14), 0.9))
    return fit(cv, 0.9)


# ------------------------------------------------------------------ DIZILIMLER
FORM_KEYS = {'std': 'std', 'tu': 'turtle', 'ar': 'arrow', 'la': 'lance', 'st': 'star', 'pi': 'pincer', 'da': 'double',
             'di': 'diamond', 'ch': 'chevron', 'mo': 'moth', 'cr': 'crab', 'he': 'heart', 'ba': 'barrage'}


def load_forms(gd_path):
    txt = open(gd_path, encoding='utf-8').read()
    out = {}
    for m in re.finditer(r'"(\w+)":\s*\n\s*(?:#[^\n]*\n\s*)?l = \[(.*?)\]\n', txt, re.S):
        pts = re.findall(r'Vector2\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\)', m.group(2))
        out[m.group(1)] = [(float(a), float(b)) for a, b in pts]
    return out


def fighter(cx, cy, s=1.0):
    pts = [(0, -95), (14, -60), (18, -10), (70, 30), (74, 52), (22, 38), (18, 62), (36, 84), (36, 96), (0, 86),
           (-36, 96), (-36, 84), (-18, 62), (-22, 38), (-74, 52), (-70, 30), (-18, -10), (-14, -60)]
    return poly([(cx + x * s, cy + y * s) for x, y in pts])


def form_icon(code, forms):
    key = FORM_KEYS[code]
    pts = forms[key]
    K = 225.0
    c = col('#43d7ff')
    cv = canvas()
    cx = cy = C
    # zemin: koyu mavi radar diski + birim halka
    disc = circle(cx, cy, 355)
    bg = radial_fill(cx, cy, 355, (0.07, 0.15, 0.24), (0.02, 0.05, 0.09), 1.1)
    cv = over(cv, np.dstack([bg * disc[..., None] * 0.9, disc * 0.9]))
    rim = ring(cx, cy, 355, 351)
    cv = add(cv, np.dstack([c[None, None, :] * rim[..., None] * 0.55, rim * 0.55]))
    ur = ring(cx, cy, K + 2, K - 2)
    cv = add(cv, np.dstack([c[None, None, :] * ur[..., None] * 0.28, ur * 0.28]))
    # gemi
    ship = fighter(cx, cy, 1.45)
    cv = shadow(cv, ship, 4, 8, 8, 0.5)
    cv = over(cv, metal_plate(ship, col('#dfe6f2'), col('#58647a'), 12, metal=0.6, spec=0.8))
    cv = over(cv, flat(ellipse(cx, cy - 50, 10, 25), (0.12, 0.2, 0.3), 0.95))
    cv = add(cv, glow_layer(circle(cx, cy + 135, 13), col('#ff9a2a'), 22, 1.0, 0.7))
    # droidler
    P = [(cx + u * K, cy - f * K) for (u, f) in pts]
    orb_all = blank()
    for (px, py) in P:
        orb_all = np.maximum(orb_all, circle(px, py, 40))
    cv = shadow(cv, orb_all, 4, 8, 8, 0.45)
    for (px, py) in P:
        o = circle(px, py, 40)
        cv = add(cv, glow_layer(circle(px, py, 40), c, 24, 0.7, 0.0))
        h = height_dome(o, 1.1, 1.5)
        lay = lit(o, h, col('#e9f4ff'), col('#25415f'), spec=0.9, shin=22, amb=0.28, dif=0.95, metal=0.5,
                  env=DARKMETAL, outline=2.5)
        cv = over(cv, lay)
        core = circle(px, py, 16)
        cv = add(cv, glow_layer(core, c, 7, 1.0, 0.8))
        cv = over(cv, flat(core, (0.75, 0.95, 1.0), 0.95))
    return fit(cv, 0.94, maxscale=1.0)


# ------------------------------------------------------------------ CEPHANE
AMMO = {
    'x1': dict(name='x1', c='#ff3b2f', bands=1, hot=(1, .86, .82)),
    'x2': dict(name='x2', c='#4fb8ff', bands=2, hot=(.88, .96, 1)),
    'x3': dict(name='x3', c='#3dff74', bands=3, hot=(.9, 1, .92)),
    'x4': dict(name='x4', c='#f2fbff', bands=4, hot=(1, 1, 1)),
    'sab': dict(name='SAB', c='#4fb8ff', bands=0, hot=(.88, .96, 1), kind='sab'),
    'rsb': dict(name='RSB', c='#ffc23a', bands=0, hot=(1, .97, .8), kind='rsb'),
}


def ammo_icon(aid):
    P = AMMO[aid]
    c = col(P['c'])
    cv = canvas()
    cx = C
    top, bot = 120, 650
    bw = 150
    body = rrect(cx - bw, top + 70, cx + bw, bot - 50, 36)
    cap_t = rrect(cx - bw + 24, top, cx + bw - 24, top + 110, 24)
    cap_b = rrect(cx - bw + 14, bot - 90, cx + bw - 14, bot, 26)
    every = union(body, cap_t, cap_b)
    cv = shadow(cv, every, 8, 16, 18, 0.55)
    # kontak (ust uc)
    nub = rrect(cx - 52, top - 28, cx + 52, top + 20, 18)
    cv = over(cv, metal_cyl(nub, 'y', col('#d8e0ee'), col('#566176'), spec=0.9))
    cv = over(cv, metal_cyl(cap_t, 'y', col('#aeb9cc'), col('#2c3442'), spec=0.9))
    cv = over(cv, metal_cyl(cap_b, 'y', col('#aeb9cc'), col('#2c3442'), spec=0.9))
    # cam govde (enerji sivisi)
    glass = rrect(cx - bw + 10, top + 100, cx + bw - 10, bot - 70, 26)
    hg = height_cyl(glass, 'y', 1.0, 1.5)
    # sivi icindeki renk degisimi: ortada parlak, kenarlarda koyu (silindirik)
    gy, gx = np.gradient(hg)
    fluid = lit(glass, hg, c * 0.9 + 0.1, c * 0.35, spec=0.0, amb=0.42, dif=0.8, metal=0.0, k=0.9)
    cv = over(cv, fluid)
    # ic cekirdek parlama (dikey)
    core = rrect(cx - 26, top + 130, cx + 26, bot - 100, 22)
    cv = add(cv, glow_layer(core, c, 40, 1.0, 0.7))
    cv = over(cv, flat(core, np.array(P['hot'], np.float32), 0.88))
    # yatay cerceve bantlari
    b = P['bands']
    if b:
        for i in range(b):
            yy = [520, 270, 575, 215][i]
            bm = rrect(cx - bw + 6, yy - 9, cx + bw - 6, yy + 9, 6)
            cv = over(cv, metal_cyl(bm, 'y', col('#cfd7e6'), col('#3a4354'), spec=0.8))
    # cam yansima seridi
    refl = rrect(cx - bw + 28, top + 118, cx - bw + 48, bot - 90, 10)
    cv = over(cv, flat(refl, (1, 1, 1), 0.28))
    # etiket plakasi
    if aid in ('sab', 'rsb'):
        pass
    plate = rrect(cx - 100, 340, cx + 100, 440, 16)
    cv = over(cv, metal_plate(plate, col('#232a38'), col('#0c1017'), 10, metal=0.0, spec=0.2))
    cv = over(cv, rim_highlight(plate, 0.25))
    tx = text_mask(P['name'], cx, 392, 72 if len(P['name']) <= 2 else 58)
    cv = add(cv, glow_layer(tx, c, 8, 0.5))
    cv = over(cv, flat(tx, np.clip(c * 0.45 + 0.55, 0, 1), 1.0))
    # sab / rsb ozel semboller
    if P.get('kind') == 'sab':
        for yy in (210, 560):
            arc = ring(cx, yy, 62, 52) * (blank() + (np.mgrid[0:S, 0:S][0] < yy + 5 if yy > 400 else np.mgrid[0:S, 0:S][0] > yy - 5))
            cv = add(cv, glow_layer(arc, c, 6, 0.9))
    if P.get('kind') == 'rsb':
        for sg in (-1, 1):
            sp = poly([(cx + sg * bw, 250), (cx + sg * (bw + 70), 210), (cx + sg * (bw + 40), 330), (cx + sg * bw, 360)])
            cv = over(cv, metal_plate(sp, col('#ffe08a'), col('#8c5f10'), 10, metal=0.7))
            sp2 = poly([(cx + sg * bw, 440), (cx + sg * (bw + 70), 480), (cx + sg * (bw + 40), 560), (cx + sg * bw, 560)])
            cv = over(cv, metal_plate(sp2, col('#ffe08a'), col('#8c5f10'), 10, metal=0.7))
    return fit(cv, 0.9)


# ------------------------------------------------------------------ ROKET
def rocket_icon():
    cv = canvas()
    cy = C
    body = rrect(230, cy - 62, 560, cy + 62, 24)
    nose = poly([(548, cy - 62)] + [(548 + 160 * math.sin(t / 20 * math.pi / 2) * 0.95 + 0, cy - 62 * math.cos(t / 20 * math.pi / 2) ** 1.25) for t in range(1, 20)] + [(704, cy)] +
                [(548 + 160 * math.sin(t / 20 * math.pi / 2) * 0.95, cy + 62 * math.cos(t / 20 * math.pi / 2) ** 1.25) for t in range(19, 0, -1)] + [(548, cy + 62)])
    # yuzgec
    fins = blank()
    for sg in (-1, 1):
        fins = np.maximum(fins, poly([(250, cy + sg * 52), (330, cy + sg * 52), (210, cy + sg * 170), (160, cy + sg * 170), (190, cy + sg * 52)]))
    nozzle = rrect(180, cy - 44, 250, cy + 44, 14)
    # alev
    flame = poly([(190, cy - 34)] + [(190 - 190 * (i / 14) ** 0.8, cy - 34 * (1 - i / 14) ** 0.9) for i in range(1, 14)] + [(0, cy)] +
                 [(190 - 190 * (i / 14) ** 0.8, cy + 34 * (1 - i / 14) ** 0.9) for i in range(13, 0, -1)] + [(190, cy + 34)])
    every = union(body, nose, fins, nozzle)
    cv = shadow(cv, every, 8, 16, 16, 0.5)
    cv = add(cv, glow_layer(flame, col('#ff7a1a'), 40, 1.0, 0.5))
    cv = over(cv, flat(flame, col('#ff7a1a'), 0.95))
    cv = over(cv, flat(blur(flame, 4) * (1 - 0) * (poly([(190, cy - 18), (60, cy), (190, cy + 18)])), col('#ffd46a'), 1.0))
    cv = over(cv, flat(poly([(190, cy - 8), (120, cy), (190, cy + 8)]), (1, 1, 0.92), 1.0))
    # yuzgecler
    cv = over(cv, metal_plate(fins, col('#ff6a52'), col('#7a1710'), 12, metal=0.4, spec=0.7))
    cv = over(cv, metal_cyl(nozzle, 'x', col('#9aa6b8'), col('#232a37'), spec=0.9))
    cv = over(cv, metal_cyl(body, 'x', col('#f2f5fa'), col('#7c8699'), spec=0.9, metal=0.5, env=CHROME))
    # uyari seritleri
    for x0 in (330, 360, 390):
        band = rrect(x0, cy - 62, x0 + 14, cy + 62, 3)
        cv = over(cv, flat(band, (0.08, 0.09, 0.12), 0.85))
    band2 = rrect(440, cy - 62, 500, cy + 62, 4)
    bl = lit(band2, height_cyl(band2, 'x', 1.0, 1.2), col('#ffd24a'), col('#a8710a'), spec=0.6, amb=0.3, dif=0.9)
    cv = over(cv, bl)
    cv = over(cv, metal_cyl(nose, 'x', col('#ff6a52'), col('#9a1d14'), spec=0.95, metal=0.0))
    cv = over(cv, rim_highlight(nose, 0.3))
    # R-310 yazisi
    cv = over(cv, flat(np.clip(text_mask('R-310', 305, cy + 0, 30), 0, 1) * body * 0, (0, 0, 0), 0))
    cv = transform(cv, 36, 1.0, 0, 0)
    return fit(cv, 0.9)


def build(outdir_items, outdir_ui, gd_path):
    os.makedirs(outdir_items, exist_ok=True)
    os.makedirs(outdir_ui, exist_ok=True)
    finish(drone_flax(), os.path.join(outdir_items, 'drone_flax.png'))
    finish(drone_iris(), os.path.join(outdir_items, 'drone_iris.png'))
    forms = load_forms(gd_path)
    for code in FORM_KEYS:
        finish(form_icon(code, forms), os.path.join(outdir_items, 'form_%s.png' % code))
    for a in AMMO:
        finish(ammo_icon(a), os.path.join(outdir_ui, 'ammo_%s.png' % a))
    r = rocket_icon()
    finish(r, os.path.join(outdir_ui, 'rocket_r310.png'))
    finish(r, os.path.join(outdir_ui, 'rocket.png'))


if __name__ == '__main__':
    build('/home/claude/out_test', '/home/claude/out_test', '/home/claude/net/drone_forms.gd')
