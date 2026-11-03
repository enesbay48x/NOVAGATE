from iconlib import *

STEEL_T = col('#8d99ab')
STEEL_B = col('#2d3544')
DARK_T = col('#4a5365')
DARK_B = col('#161b26')


def metal_cyl(mask, axis='x', top=STEEL_T, bot=STEEL_B, spec=0.7, metal=0.75, env=None, rs=1.0):
    h = height_cyl(mask, axis, radius_scale=rs, soft=1.2)
    return lit(mask, h, top, bot, spec=spec, shin=30, amb=0.25, dif=0.9, metal=metal, env=DARKMETAL if env is None else env, k=0.9, outline=3)


def metal_plate(mask, top=STEEL_T, bot=STEEL_B, bevel=16, spec=0.5, metal=0.55, k=1.0):
    h = height_bevel(mask, bevel, 2.2)
    return lit(mask, h, top, bot, spec=spec, shin=26, amb=0.28, dif=0.95, metal=metal, env=DARKMETAL, k=k, outline=3)


def energy_slot(cv, mask, color, hot=(1, 1, 1), power=1.0):
    """Cam/enerji penceresi: koyu govde + parlak cekirdek."""
    c = np.array(color, np.float32)
    inner = blur(mask, 6)
    d = ndi.distance_transform_edt(mask > 0.5).astype(np.float32)
    t = np.clip(d / (d.max() + 1e-6), 0, 1)
    rgb = lerp((c * 0.30)[None, None, :], np.array(hot, np.float32)[None, None, :], (t ** 1.4)[..., None])
    rgb = rgb * (0.65 + 0.7 * power)
    lay = np.dstack([np.clip(rgb, 0, 1) * mask[..., None], mask])
    cv = over(cv, lay)
    cv = add(cv, glow_layer(mask, color, 26, 0.9 * power, 0.35 * power))
    return cv


def laser_icon(kind):
    P = {
        'lf1': dict(c='#ff3b2f', hot=(1, .86, .8), barrels=1, bh=70, fins=0, thick=0),
        'lf2': dict(c='#3dff6a', hot=(.88, 1, .9), barrels=2, bh=54, fins=1, thick=0),
        'lf3': dict(c='#2fb4ff', hot=(.85, .97, 1), barrels=1, bh=112, fins=3, thick=1),
        'lf4': dict(c='#b04dff', hot=(.96, .88, 1), barrels=2, bh=92, fins=3, thick=1),
    }[kind]
    c = col(P['c'])
    cv = canvas()
    cy = C
    # ---- namlular (arkadan one)
    barrels = []
    bh = P['bh']
    if P['barrels'] == 1:
        ys = [cy]
    else:
        gap = bh * 0.55
        ys = [cy - bh / 2 - gap / 2, cy + bh / 2 + gap / 2]
    x_start, x_end = 300, 650
    layers_shadow = blank()
    parts = []
    for yy in ys:
        m = rrect(x_start, yy - bh / 2, x_end, yy + bh / 2, bh * 0.18)
        parts.append(m)
        layers_shadow = np.maximum(layers_shadow, m)
    # govde
    body_h = (ys[-1] - ys[0]) + bh + (80 if P['thick'] else 60)
    body = rrect(170, cy - body_h / 2, 400, cy + body_h / 2, 36)
    rear = rrect(100, cy - body_h * 0.36, 210, cy + body_h * 0.36, 28)
    layers_shadow = np.maximum(layers_shadow, np.maximum(body, rear))
    cv = shadow(cv, layers_shadow, 8, 16, 16, 0.5)
    # arka tutucu
    cv = over(cv, metal_plate(rear, DARK_T, DARK_B, 14))
    # namlu tupleri
    for m in parts:
        cv = over(cv, metal_cyl(m, 'x'))
    # enerji borusu (ince, namlu uzerinde parlayan cizgi)
    for yy in ys:
        tube = rrect(430, yy - 7, 610, yy + 7, 7)
        cv = add(cv, glow_layer(tube, c, 10, 0.8))
        cv = over(cv, flat(tube, np.clip(c * 0.6 + 0.4, 0, 1), 0.95))
        cv = over(cv, flat(rrect(435, yy - 2, 605, yy + 2, 2), P['hot'], 0.95))
    # halkalar (sogutma fin / sıkıştırma)
    fin_x = np.linspace(445, 560, max(P['fins'], 1)) if P['fins'] else []
    for fx in fin_x:
        y0 = ys[0] - bh / 2 - 12
        y1 = ys[-1] + bh / 2 + 12
        fm = rrect(fx - 10, y0, fx + 10, y1, 8)
        cv = over(cv, metal_cyl(fm, 'y', STEEL_T, STEEL_B, metal=0.8))
    # agiz halkasi
    for yy in ys:
        mz = rrect(612, yy - bh / 2 - 12, 660, yy + bh / 2 + 12, 12)
        cv = over(cv, metal_cyl(mz, 'x', col('#a7b2c4'), col('#3a4354'), spec=0.9))
        em = rrect(650, yy - bh * 0.28, 664, yy + bh * 0.28, 6)
        cv = over(cv, flat(em, (0.04, 0.05, 0.07), 1))
    # ana govde
    cv = over(cv, metal_plate(body, STEEL_T, STEEL_B, 20, metal=0.6))
    # govde uzerinde panel detayi
    cv = over(cv, panel_lines(body, [('v', 262, cy - body_h / 2 + 10, cy + body_h / 2 - 10),
                                     ('h', cy - body_h / 2 + 30, 180, 395),
                                     ('h', cy + body_h / 2 - 32, 180, 395)], (0, 0, 0), 0.45, 3))
    # enerji penceresi
    slot_h = body_h * 0.42
    slot = rrect(290, cy - slot_h / 2, 380, cy + slot_h / 2, 16)
    cv = energy_slot(cv, slot, c, P['hot'], 1.0)
    cv = over(cv, rim_highlight(slot, 0.25))
    # sol parlak vurgu seridi (renkli aksan)
    acc = rrect(190, cy - body_h / 2 + 12, 250, cy - body_h / 2 + 24, 6)
    cv = over(cv, flat(acc, c, 0.95))
    acc2 = rrect(190, cy + body_h / 2 - 24, 250, cy + body_h / 2 - 12, 6)
    cv = over(cv, flat(acc2, c, 0.95))
    # vidalar
    for (sx, sy) in [(205, cy - body_h / 2 + 52), (205, cy + body_h / 2 - 52), (370, cy - body_h / 2 + 22), (370, cy + body_h / 2 - 22)]:
        sc = circle(sx, sy, 9)
        cv = over(cv, metal_plate(sc, col('#c4cde0'), col('#4b566b'), 6, metal=0.6))
    # lf4: orta kristal cekirdek
    if kind == 'lf4':
        mid = rrect(330, cy - 16, 640, cy + 16, 16)
        cv = add(cv, glow_layer(mid, c, 14, 0.9))
        cv = over(cv, flat(mid, np.clip(c * 0.7 + 0.3, 0, 1), 0.95))
        cv = over(cv, flat(rrect(335, cy - 5, 636, cy + 5, 5), P['hot'], 1))
    # agiz isigi + kisa atis
    for yy in ys:
        mz = circle(668, yy, bh * 0.34)
        cv = add(cv, glow_layer(mz, c, 30, 1.0, 0.6))
        cv = add(cv, glow_layer(circle(670, yy, bh * 0.14), P['hot'], 8, 1.0, 0.8))
    # tum katmani dondur
    cv = transform(cv, 34, 1.0, 0, 0)
    return fit(cv, 0.84)


def build(outdir):
    import os
    os.makedirs(outdir, exist_ok=True)
    for k in ('lf1', 'lf2', 'lf3', 'lf4'):
        finish(laser_icon(k), os.path.join(outdir, 'weapon_%s.png' % k))


if __name__ == '__main__':
    build('/home/claude/out_test')
