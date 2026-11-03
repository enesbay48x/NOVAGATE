# GLB onizleme (yazilimsal z-buffer cizici). Sadece dogrulama icin.
import json, struct, sys, math
import numpy as np
from PIL import Image

def load(path):
    b = open(path, 'rb').read()
    jl = struct.unpack('<I', b[12:16])[0]
    j = json.loads(b[20:20 + jl]); binb = b[20 + jl + 8:]
    def acc(i, dt, n):
        a = j['accessors'][i]; v = j['bufferViews'][a['bufferView']]
        arr = np.frombuffer(binb, dt, a['count'] * n, v['byteOffset'])
        return arr.reshape(a['count'], n) if n > 1 else arr
    out = []
    for pr in j['meshes'][0]['primitives']:
        out.append((acc(pr['attributes']['POSITION'], np.float32, 3), acc(pr['attributes']['NORMAL'], np.float32, 3),
                    acc(pr['indices'], np.uint32, 1).reshape(-1, 3), j['materials'][pr['material']]))
    return out

def render(parts, yaw, pitch, size=520, bg=(14, 22, 34), cull=True):
    ss = 2; W = size * ss
    R = (np.array([[1,0,0],[0,math.cos(pitch),-math.sin(pitch)],[0,math.sin(pitch),math.cos(pitch)]]) @
         np.array([[math.cos(yaw),0,math.sin(yaw)],[0,1,0],[-math.sin(yaw),0,math.cos(yaw)]]))
    allp = np.vstack([p[0] for p in parts]) @ R.T; sc = W * 0.42 / np.abs(allp[:, :2]).max()
    L = np.array([-0.45, 0.75, 0.55]); L /= np.linalg.norm(L)
    zb = np.full((W, W), -1e9); img = np.zeros((W, W, 3), np.float32); img[:] = np.array(bg) / 255.0
    flipped = 0
    for P, N, I, m in parts:
        Pc = P @ R.T; Nc = N @ R.T
        pm = m['pbrMetallicRoughness']; base = np.array(pm['baseColorFactor'][:3]); met = pm['metallicFactor']
        em = np.array(m.get('emissiveFactor', [0, 0, 0])); k = m.get('extensions', {}).get('KHR_materials_emissive_strength', {}).get('emissiveStrength', 1.0)
        for t in I:
            a, b, c = Pc[t[0]], Pc[t[1]], Pc[t[2]]
            gn = np.cross(b - a, c - a)
            if cull and gn[2] <= 0: continue
            nn = (Nc[t[0]] + Nc[t[1]] + Nc[t[2]]); nn = nn / (np.linalg.norm(nn) + 1e-9)
            lam = max(0.0, float(nn @ (L))) * 0.85 + 0.22
            spec = max(0.0, float(nn @ np.array([0.0, 0.3, 0.95]))) ** 24 * (0.3 + 0.7 * met)
            col = base * lam * (1 - 0.3 * met) + spec * 0.6 + em * min(k, 2.4) * 0.45
            X = np.array([W / 2 + p[0] * sc for p in (a, b, c)]); Y = np.array([W / 2 - p[1] * sc for p in (a, b, c)]); Z = np.array([a[2], b[2], c[2]])
            x0, x1 = int(max(0, math.floor(X.min()))), int(min(W - 1, math.ceil(X.max())))
            y0, y1 = int(max(0, math.floor(Y.min()))), int(min(W - 1, math.ceil(Y.max())))
            if x1 < x0 or y1 < y0: continue
            xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            d = (Y[1] - Y[2]) * (X[0] - X[2]) + (X[2] - X[1]) * (Y[0] - Y[2])
            if abs(d) < 1e-9: continue
            w0 = ((Y[1] - Y[2]) * (xs - X[2]) + (X[2] - X[1]) * (ys - Y[2])) / d
            w1 = ((Y[2] - Y[0]) * (xs - X[2]) + (X[0] - X[2]) * (ys - Y[2])) / d
            w2 = 1 - w0 - w1
            inside = (w0 >= -1e-4) & (w1 >= -1e-4) & (w2 >= -1e-4)
            z = w0 * Z[0] + w1 * Z[1] + w2 * Z[2]
            sub = zb[y0:y1 + 1, x0:x1 + 1]
            upd = inside & (z > sub)
            sub[upd] = z[upd]
            img[y0:y1 + 1, x0:x1 + 1][upd] = np.clip(col, 0, 1)
    im = Image.fromarray((img * 255).astype(np.uint8)).resize((size, size), Image.LANCZOS)
    return im

if __name__ == '__main__':
    out = sys.argv[1]; files = sys.argv[2:]; tiles = []
    for f in files:
        parts = load(f)
        tiles.append(render(parts, 0, math.radians(80)))
        tiles.append(render(parts, math.radians(-35), math.radians(35)))
    Wd = Image.new('RGB', (520 * len(tiles), 520))
    for i, t in enumerate(tiles): Wd.paste(t, (520 * i, 0))
    Wd.save(out)
