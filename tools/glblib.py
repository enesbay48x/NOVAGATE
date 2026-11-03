# Kucuk prosedurel mesh + GLB (glTF 2.0) yazici. Harici kutuphane gerektirmez (sadece numpy).
import json, struct, math
import numpy as np


def rx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], np.float64)


def ry(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], np.float64)


def rz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], np.float64)


I3 = np.eye(3)


class Mesh:
    def __init__(self):
        self.mats = []          # [{name, base, metal, rough, emit, emit_k}]
        self.prims = {}         # mat index -> dict(p=[], n=[], i=[])

    def mat(self, name, base, metal=0.3, rough=0.5, emit=None, emit_k=1.0):
        self.mats.append(dict(name=name, base=list(base), metal=metal, rough=rough, emit=emit, emit_k=emit_k))
        idx = len(self.mats) - 1
        self.prims[idx] = dict(p=[], n=[], i=[])
        return idx

    # ---- temel: ucgen listesi ekle (vertex normalleri verilir; sarma yonu normale gore duzeltilir)
    def _emit(self, m, P, N, T, R=I3, t=(0, 0, 0)):
        P = np.asarray(P, np.float64) @ R.T + np.asarray(t, np.float64)
        N = np.asarray(N, np.float64) @ R.T
        N /= (np.linalg.norm(N, axis=1, keepdims=True) + 1e-12)
        T = np.asarray(T, np.int64).copy()
        a, b, c = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
        gn = np.cross(b - a, c - a)
        vn = N[T[:, 0]] + N[T[:, 1]] + N[T[:, 2]]
        flip = (gn * vn).sum(1) < 0
        T[flip] = T[flip][:, [0, 2, 1]]
        pr = self.prims[m]
        base = sum(len(x) for x in pr['p'])
        pr['p'].append(P.astype(np.float32))
        pr['n'].append(N.astype(np.float32))
        pr['i'].append((T + base).astype(np.uint32))

    # ---- duz yuzlu cokgen (konveks) - tek normal
    def _poly_flat(self, m, pts, normal, R, t):
        pts = np.asarray(pts, np.float64)
        c = pts.mean(0)
        P = np.vstack([c[None], pts])
        n = len(pts)
        T = [[0, 1 + i, 1 + (i + 1) % n] for i in range(n)]
        N = np.tile(np.asarray(normal, np.float64), (n + 1, 1))
        self._emit(m, P, N, T, R, t)

    def quad(self, m, a, b, c, d, R=I3, t=(0, 0, 0), out=None):
        a, b, c, d = [np.asarray(x, np.float64) for x in (a, b, c, d)]
        n = np.cross(b - a, c - a)
        if np.linalg.norm(n) < 1e-12:
            n = np.cross(c - a, d - a)
        if out is not None and np.dot(n, np.asarray(out, np.float64)) < 0:
            n = -n          # normal DISARI baksin
        self._poly_flat(m, [a, b, c, d], n, R, t)

    # ---- kutu
    def box(self, m, size, R=I3, t=(0, 0, 0), center=(0, 0, 0)):
        sx, sy, sz = [s / 2.0 for s in size]
        cx, cy, cz = center
        v = lambda x, y, z: (cx + x * sx, cy + y * sy, cz + z * sz)
        faces = [((1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)), ((-1, -1, 1), (-1, 1, 1), (-1, 1, -1), (-1, -1, -1)),
                 ((-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1)), ((-1, -1, 1), (-1, -1, -1), (1, -1, -1), (1, -1, 1)),
                 ((-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)), ((1, -1, -1), (-1, -1, -1), (-1, 1, -1), (1, 1, -1))]
        for f in faces:
            ctr = np.mean([v(*p) for p in f], 0) - np.array([cx, cy, cz])
            self.quad(m, *[v(*p) for p in f], R=R, t=t, out=ctr)

    # ---- dondurme govdesi (profil: [(yaricap, yukseklik)...]); smooth=True -> yumusak normal
    def lathe(self, m, profile, segs=24, smooth=False, R=I3, t=(0, 0, 0), scale=(1, 1, 1)):
        prof = np.asarray(profile, np.float64)
        n = len(prof)
        th = np.linspace(0, 2 * math.pi, segs + 1)
        sc = np.asarray(scale, np.float64)

        def ring(r, y):
            return np.stack([r * np.cos(th), np.full_like(th, y), r * np.sin(th)], 1)

        def seg_normal(p0, p1):
            dr, dy = p1[0] - p0[0], p1[1] - p0[1]
            L = math.hypot(dr, dy) + 1e-12
            return (dy / L, -dr / L)   # (n_r, n_y)

        if smooth:
            nr = np.zeros((n, 2))
            for i in range(n - 1):
                s = np.array(seg_normal(prof[i], prof[i + 1]))
                nr[i] += s
                nr[i + 1] += s
            nr /= (np.linalg.norm(nr, axis=1, keepdims=True) + 1e-12)
            P = np.vstack([ring(*prof[i]) for i in range(n)])
            N = np.vstack([np.stack([nr[i][0] * np.cos(th), np.full_like(th, nr[i][1]), nr[i][0] * np.sin(th)], 1) for i in range(n)])
            T = []
            w = segs + 1
            for i in range(n - 1):
                for j in range(segs):
                    a, b, c, d = i * w + j, i * w + j + 1, (i + 1) * w + j + 1, (i + 1) * w + j
                    T += [[a, b, c], [a, c, d]]
            self._emit(self._cur(m), P * sc, N / sc, T, R, t)
        else:
            for i in range(n - 1):
                p0, p1 = prof[i], prof[i + 1]
                if abs(p0[0]) < 1e-9 and abs(p1[0]) < 1e-9:
                    continue
                nrm = seg_normal(p0, p1)
                P = np.vstack([ring(*p0), ring(*p1)])
                N = np.stack([nrm[0] * np.cos(np.r_[th, th]), np.full(2 * len(th), nrm[1]), nrm[0] * np.sin(np.r_[th, th])], 1)
                w = segs + 1
                T = []
                for j in range(segs):
                    T += [[j, j + 1, w + j + 1], [j, w + j + 1, w + j]]
                self._emit(self._cur(m), P * sc, N / sc, T, R, t)

    def _cur(self, m):
        return m

    # ---- prizma / loft: konveks cokgen (x,z duzleminde), y0..y1, ust yuz 'inset' orani kadar kuculur
    def prism(self, m, poly_xz, y0, y1, inset=1.0, R=I3, t=(0, 0, 0), mid=None):
        pts = np.asarray(poly_xz, np.float64)
        c = pts.mean(0)
        rings = [(y0, 1.0)]
        if mid is not None:
            rings.append((mid[0], mid[1]))
        rings.append((y1, inset))
        n = len(pts)
        for k in range(len(rings) - 1):
            ya, sa = rings[k]
            yb, sb = rings[k + 1]
            A = [np.array([c[0] + (p[0] - c[0]) * sa, ya, c[1] + (p[1] - c[1]) * sa]) for p in pts]
            B = [np.array([c[0] + (p[0] - c[0]) * sb, yb, c[1] + (p[1] - c[1]) * sb]) for p in pts]
            for i in range(n):
                j = (i + 1) % n
                mid_ = (A[i] + A[j] + B[i] + B[j]) / 4.0
                self.quad(m, A[i], A[j], B[j], B[i], R, t, out=(mid_[0] - c[0], 0.0, mid_[2] - c[1]))
        ya, sa = rings[0]
        yb, sb = rings[-1]
        top = [(c[0] + (p[0] - c[0]) * sb, yb, c[1] + (p[1] - c[1]) * sb) for p in pts]
        bot = [(c[0] + (p[0] - c[0]) * sa, ya, c[1] + (p[1] - c[1]) * sa) for p in pts]
        self._poly_flat(m, top, (0, 1, 0), R, t)
        self._poly_flat(m, bot, (0, -1, 0), R, t)

    def sphere(self, m, r, segs=20, rings=12, R=I3, t=(0, 0, 0), scale=(1, 1, 1), hemi=False):
        a0, a1 = (0.0, math.pi / 2) if hemi else (-math.pi / 2, math.pi / 2)
        prof = [(r * math.cos(a), r * math.sin(a)) for a in np.linspace(a0, a1, rings)]
        if hemi:
            prof = prof[::-1][::-1]
        prof = [(max(p[0], 0.0), p[1]) for p in prof]
        self.lathe(m, prof, segs, True, R, t, scale)

    def cylz(self, m, r, z0, z1, segs=20, x=0.0, y=0.0, caps=True, smooth=True):
        """Z ekseninde silindir (z0 -> z1)."""
        prof = [(0, z0), (r, z0), (r, z1), (0, z1)] if caps else [(r, z0), (r, z1)]
        # lathe y ekseninde calisir -> Rx(90): y -> z
        self.lathe(m, prof, segs, False if caps else True, rx(math.pi / 2), (x, y, 0))
        # not: rx(+90): (x,y,z) -> (x,-z,y)  => yukseklik y, z'ye gelir

    # ---- GLB yaz
    def save(self, path, name='mesh'):
        bin_parts, views, accs, prims, mats = [], [], [], [], []

        def add_view(data, target):
            off = sum(len(b) for b in bin_parts)
            pad = (-off) % 4
            if pad:
                bin_parts.append(b'\0' * pad)
                off += pad
            bin_parts.append(data)
            views.append(dict(buffer=0, byteOffset=off, byteLength=len(data), target=target))
            return len(views) - 1

        used = [i for i, pr in self.prims.items() if pr['p']]
        for mi in used:
            pr = self.prims[mi]
            P = np.vstack(pr['p']).astype(np.float32)
            N = np.vstack(pr['n']).astype(np.float32)
            Ix = np.vstack(pr['i']).astype(np.uint32).reshape(-1)
            vp = add_view(P.tobytes(), 34962)
            vn = add_view(N.tobytes(), 34962)
            vi = add_view(Ix.tobytes(), 34963)
            accs.append(dict(bufferView=vp, componentType=5126, count=len(P), type='VEC3', min=P.min(0).tolist(), max=P.max(0).tolist()))
            ap = len(accs) - 1
            accs.append(dict(bufferView=vn, componentType=5126, count=len(N), type='VEC3'))
            an = len(accs) - 1
            accs.append(dict(bufferView=vi, componentType=5125, count=len(Ix), type='SCALAR'))
            ai = len(accs) - 1
            prims.append(dict(attributes=dict(POSITION=ap, NORMAL=an), indices=ai, material=used.index(mi), mode=4))
            m = self.mats[mi]
            gm = dict(name=m['name'], pbrMetallicRoughness=dict(baseColorFactor=m['base'] + [1.0], metallicFactor=m['metal'], roughnessFactor=m['rough']))
            if m['emit'] is not None:
                gm['emissiveFactor'] = [min(1.0, c) for c in m['emit']]
                if m['emit_k'] != 1.0:
                    gm['extensions'] = {'KHR_materials_emissive_strength': {'emissiveStrength': m['emit_k']}}
            mats.append(gm)
        binary = b''.join(bin_parts)
        binary += b'\0' * ((-len(binary)) % 4)
        j = dict(asset=dict(version='2.0', generator='novagate-procedural'),
                 extensionsUsed=['KHR_materials_emissive_strength'],
                 scene=0, scenes=[dict(nodes=[0])], nodes=[dict(name=name, mesh=0)],
                 meshes=[dict(name=name, primitives=prims)], materials=mats, accessors=accs, bufferViews=views,
                 buffers=[dict(byteLength=len(binary))])
        js = json.dumps(j, separators=(',', ':')).encode()
        js += b' ' * ((-len(js)) % 4)
        total = 12 + 8 + len(js) + 8 + len(binary)
        with open(path, 'wb') as f:
            f.write(struct.pack('<4sII', b'glTF', 2, total))
            f.write(struct.pack('<I4s', len(js), b'JSON') + js)
            f.write(struct.pack('<I4s', len(binary), b'BIN\0') + binary)
        return path
