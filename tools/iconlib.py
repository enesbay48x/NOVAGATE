# NOVAGATE market ikon cizim kutuphanesi. Tamamen prosedurel, harici gorsel kullanmaz.
# Tum katmanlar "premultiplied" float RGBA (H,W,4) olarak tutulur.
import numpy as np
import cv2
from scipy import ndimage as ndi

S = 768          # calisma cozunurlugu (cikti 256'ya kucultulur)
C = S / 2.0


def canvas():
    return np.zeros((S, S, 4), np.float32)


def col(h):
    """'#rrggbb' -> float rgb"""
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


def lerp(a, b, t):
    return a + (b - a) * t


# ------------------------------------------------------------------ maskeler
def blank():
    return np.zeros((S, S), np.float32)


def _aa(draw_fn, ss=3):
    """Yuksek cozunurlukte ciz, kucult: yumusak kenarli maske."""
    big = np.zeros((S * ss, S * ss), np.uint8)
    draw_fn(big, ss)
    m = cv2.resize(big, (S, S), interpolation=cv2.INTER_AREA).astype(np.float32) / 255.0
    return m


def poly(pts, ss=3):
    def f(img, k):
        p = (np.array(pts, np.float64) * k).astype(np.int32)
        cv2.fillPoly(img, [p], 255, lineType=cv2.LINE_AA)
    return _aa(f, ss)


def ellipse(cx, cy, rx, ry, ang=0, ss=3):
    def f(img, k):
        cv2.ellipse(img, (int(cx * k), int(cy * k)), (int(rx * k), int(ry * k)), ang, 0, 360, 255, -1, cv2.LINE_AA)
    return _aa(f, ss)


def circle(cx, cy, r):
    return ellipse(cx, cy, r, r)


def ring(cx, cy, r_out, r_in):
    return np.clip(circle(cx, cy, r_out) - circle(cx, cy, r_in), 0, 1)


def rrect(x0, y0, x1, y1, r, ss=3):
    def f(img, k):
        X0, Y0, X1, Y1, R = [int(v * k) for v in (x0, y0, x1, y1, r)]
        R = max(0, min(R, (X1 - X0) // 2, (Y1 - Y0) // 2))
        cv2.rectangle(img, (X0 + R, Y0), (X1 - R, Y1), 255, -1)
        cv2.rectangle(img, (X0, Y0 + R), (X1, Y1 - R), 255, -1)
        for (cx, cy) in ((X0 + R, Y0 + R), (X1 - R, Y0 + R), (X0 + R, Y1 - R), (X1 - R, Y1 - R)):
            cv2.circle(img, (cx, cy), R, 255, -1, cv2.LINE_AA)
    return _aa(f, ss)


def line(p0, p1, w, ss=3):
    def f(img, k):
        cv2.line(img, (int(p0[0] * k), int(p0[1] * k)), (int(p1[0] * k), int(p1[1] * k)), 255, int(w * k), cv2.LINE_AA)
    return _aa(f, ss)


def union(*ms):
    out = blank()
    for m in ms:
        out = np.maximum(out, m)
    return out


def blur(m, s):
    return cv2.GaussianBlur(m, (0, 0), s) if s > 0 else m


# ------------------------------------------------------------------ isik / golgelendirme
def _norm(v):
    return v / (np.linalg.norm(v) + 1e-9)


LIGHT = _norm(np.array([-0.55, -0.75, 0.62], np.float32))


def height_bevel(mask, bevel=16.0, soft=2.0):
    d = ndi.distance_transform_edt(mask > 0.5).astype(np.float32)
    t = np.clip(d / bevel, 0, 1)
    h = (t * t * (3 - 2 * t)) * bevel
    return blur(h, soft)


def height_cyl(mask, axis='x', radius_scale=1.0, soft=1.0):
    """Silindirik profil: eksen boyunca duz, enine yarim daire."""
    m = mask > 0.5
    h = np.zeros_like(mask)
    if axis == 'x':
        for x in range(S):
            ys = np.where(m[:, x])[0]
            if len(ys) < 2:
                continue
            y0, y1 = ys[0], ys[-1]
            c = (y0 + y1) / 2.0
            r = (y1 - y0) / 2.0 + 0.5
            yy = np.arange(y0, y1 + 1)
            t = np.clip((yy - c) / r, -1, 1)
            h[y0:y1 + 1, x] = np.sqrt(1 - t * t) * r * radius_scale
    else:
        for y in range(S):
            xs = np.where(m[y, :])[0]
            if len(xs) < 2:
                continue
            x0, x1 = xs[0], xs[-1]
            c = (x0 + x1) / 2.0
            r = (x1 - x0) / 2.0 + 0.5
            xx = np.arange(x0, x1 + 1)
            t = np.clip((xx - c) / r, -1, 1)
            h[y, x0:x1 + 1] = np.sqrt(1 - t * t) * r * radius_scale
    return blur(h, soft)


def height_dome(mask, k=1.0, soft=2.0):
    d = ndi.distance_transform_edt(mask > 0.5).astype(np.float32)
    dm = d.max() + 1e-6
    t = d / dm
    return blur(np.sqrt(1 - (1 - t) ** 2) * dm * k, soft)


def lit(mask, h, c_top, c_bot=None, spec=0.55, shin=40.0, amb=0.30, dif=0.85, metal=0.0,
        env=None, k=1.0, outline=0.0, outline_col=(0.02, 0.03, 0.05), emit=0.0, y_range=None):
    """Yukseklik haritasindan isikli katman. Premultiplied RGBA dondurur."""
    gy, gx = np.gradient(h)
    n = np.dstack([-gx * k, -gy * k, np.ones_like(h)])
    n /= (np.linalg.norm(n, axis=2, keepdims=True) + 1e-9)
    ndl = np.clip((n * LIGHT).sum(2), 0, 1)
    hv = _norm(LIGHT + np.array([0, 0, 1.0], np.float32))
    nds = np.clip((n * hv).sum(2), 0, 1) ** shin
    c_top = np.array(c_top, np.float32)
    c_bot = c_top if c_bot is None else np.array(c_bot, np.float32)
    ys = np.where(mask.max(1) > 0.5)[0]
    y0, y1 = (ys[0], ys[-1]) if len(ys) else (0, S - 1)
    if y_range:
        y0, y1 = y_range
    ty = np.clip((np.arange(S, dtype=np.float32) - y0) / max(1, (y1 - y0)), 0, 1)[:, None, None]
    base = lerp(c_top[None, None, :], c_bot[None, None, :], ty)
    shade = amb + dif * ndl[..., None]
    rgb = base * shade
    if metal > 0:
        # krom ortam haritasi: dik bileseni (ny) 1D rampaya esle
        e = env if env is not None else CHROME
        ny = np.clip(n[..., 1] * 0.5 + 0.5, 0, 1)
        idx = (ny * (len(e) - 1)).astype(np.int32)
        envc = e[idx]
        tint = base / (base.max() + 1e-6)
        rgb = lerp(rgb, envc * (0.55 + 0.9 * tint) * (0.6 + 0.6 * n[..., 2:3]), metal)
    rgb = rgb + spec * nds[..., None] * np.array([1.0, 0.98, 0.95], np.float32)
    rgb = rgb + emit * base
    a = mask.copy()
    if outline > 0:
        d = ndi.distance_transform_edt(mask > 0.5).astype(np.float32)
        edge = np.clip(1.0 - d / outline, 0, 1)[..., None] * 0.55
        rgb = lerp(rgb, np.array(outline_col, np.float32), edge)
    rgb = np.clip(rgb, 0, 1)
    return np.dstack([rgb * a[..., None], a])


# krom rampasi: gokyuzu parlak -> ufuk koyu -> zemin orta -> alt yansima
def _mk_chrome():
    stops = [(0.0, (0.10, 0.12, 0.16)), (0.12, (0.34, 0.38, 0.45)), (0.30, (0.92, 0.96, 1.0)),
             (0.46, (0.55, 0.62, 0.72)), (0.52, (0.10, 0.12, 0.16)), (0.70, (0.30, 0.34, 0.40)),
             (0.88, (0.55, 0.62, 0.72)), (1.0, (0.22, 0.26, 0.32))]
    out = np.zeros((256, 3), np.float32)
    xs = np.linspace(0, 1, 256)
    for i in range(3):
        out[:, i] = np.interp(xs, [s[0] for s in stops], [s[1][i] for s in stops])
    return out


CHROME = _mk_chrome()


def _mk_dark_metal():
    stops = [(0.0, (0.05, 0.06, 0.09)), (0.20, (0.20, 0.23, 0.29)), (0.34, (0.62, 0.68, 0.78)),
             (0.48, (0.26, 0.30, 0.37)), (0.55, (0.06, 0.07, 0.10)), (0.78, (0.16, 0.19, 0.24)),
             (0.92, (0.34, 0.39, 0.47)), (1.0, (0.12, 0.14, 0.18))]
    out = np.zeros((256, 3), np.float32)
    xs = np.linspace(0, 1, 256)
    for i in range(3):
        out[:, i] = np.interp(xs, [s[0] for s in stops], [s[1][i] for s in stops])
    return out


DARKMETAL = _mk_dark_metal()


# ------------------------------------------------------------------ birlestirme
def over(base, layer):
    return layer + base * (1 - layer[..., 3:4])


def put(base, layer):
    return over(base, layer)


def flat(mask, color, alpha=1.0):
    c = np.array(color, np.float32)
    a = mask * alpha
    return np.dstack([c[None, None, :] * a[..., None] * np.ones((S, S, 3), np.float32), a])


def glow_layer(mask, color, radius, intensity=1.0, core=0.0):
    """Isik halesi: alfa ve rgb premultiplied eklenir (additive)."""
    g = blur(mask, radius) * intensity
    if core > 0:
        g = g + blur(mask, radius * 0.35) * core
    g = np.clip(g, 0, 1)
    c = np.array(color, np.float32)
    return np.dstack([c[None, None, :] * g[..., None] * np.ones((S, S, 3), np.float32), g])


def add(base, layer):
    out = base + layer
    out[..., 3] = np.clip(base[..., 3] + layer[..., 3] * (1 - base[..., 3]), 0, 1)
    out[..., :3] = np.minimum(out[..., :3], out[..., 3:4] * 1.0 + 0.0)
    return out


def screen_in(base, mask, color, intensity=1.0):
    """Sadece mevcut piksellerin icinde isik ekle (parlak malzeme)."""
    c = np.array(color, np.float32)
    g = np.clip(mask * intensity, 0, 1)[..., None] * c[None, None, :]
    out = base.copy()
    a = base[..., 3:4]
    out[..., :3] = np.clip(base[..., :3] + g * a, 0, 1) * 1.0
    return out


def shadow(base, mask, dx=10, dy=14, blur_r=14, alpha=0.55):
    sh = np.roll(np.roll(blur(mask, blur_r), dy, 0), dx, 1) * alpha
    layer = np.dstack([np.zeros((S, S, 3), np.float32), sh])
    return over(layer, base)


# ------------------------------------------------------------------ gorsel yardimcilar
def transform(layer, angle=0.0, scale=1.0, dx=0.0, dy=0.0):
    M = cv2.getRotationMatrix2D((C, C), angle, scale)
    M[0, 2] += dx
    M[1, 2] += dy
    return cv2.warpAffine(layer, M, (S, S), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_CONSTANT, borderValue=0)


def finish(layer, path, out=256, margin=0):
    a = np.clip(layer[..., 3], 0, 1)
    rgb = np.clip(layer[..., :3], 0, 1)
    if margin:
        pass
    small = cv2.resize(np.dstack([rgb, a]), (out, out), interpolation=cv2.INTER_AREA)
    a2 = small[..., 3:4]
    rgb2 = np.where(a2 > 1e-4, small[..., :3] / np.maximum(a2, 1e-4), 0)
    img = np.dstack([np.clip(rgb2, 0, 1), np.clip(a2, 0, 1)])
    im = (img * 255 + 0.5).astype(np.uint8)
    import PIL.Image as I
    I.fromarray(im, 'RGBA').save(path, optimize=True)
    return im


def panel_lines(mask, h_lines, color=(0, 0, 0), alpha=0.45, w=2):
    """Metal govdeye ince panel cizgileri (yatay/dikey) ekler: katman dondurur."""
    out = blank()
    for (kind, pos, a0, a1) in h_lines:
        if kind == 'v':
            out[int(a0):int(a1), int(pos):int(pos) + w] = 1
        else:
            out[int(pos):int(pos) + w, int(a0):int(a1)] = 1
    out *= mask
    return flat(out, color, alpha)


def rim_highlight(mask, strength=0.5, width=3, color=(1, 1, 1)):
    """Ust-sol kenarda ince parlak cizgi."""
    d = ndi.distance_transform_edt(mask > 0.5).astype(np.float32)
    edge = np.clip(1 - np.abs(d - 2.0) / width, 0, 1) * (mask > 0.5)
    gy, gx = np.gradient(blur(mask, 3))
    facing = np.clip(-(gx * LIGHT[0] + gy * LIGHT[1]) * 14, 0, 1)
    return flat(edge * facing, color, strength)


def noise_tex(seed=1, s=1.2):
    r = np.random.RandomState(seed)
    return blur(r.rand(S, S).astype(np.float32), s)


def fit(layer, fill=0.86, shift=(0, 0), maxscale=1.9, glow_pad=0.0):
    """Icerigi (alfa > esik) kareye ortala ve doldur."""
    a = layer[..., 3]
    ys, xs = np.where(a > 0.35)
    if len(xs) == 0:
        return layer
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    w, h = x1 - x0 + 1, y1 - y0 + 1
    sc = min(maxscale, fill * S / max(w, h))
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    M = np.array([[sc, 0, C - cx * sc + shift[0]], [0, sc, C - cy * sc + shift[1]]], np.float32)
    return cv2.warpAffine(layer, M, (S, S), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_CONSTANT, borderValue=0)
