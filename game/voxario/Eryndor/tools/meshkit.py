"""meshkit – stavba stylizovaných modelů kódem (vlastní tvorba pro Eryndor).

Tvary (kvádr, válec, koule, rotační profil, kapsle), deformace šumem, „malování“ barev vrcholů
(přechody, zastínění, šum – vzhled ručně malovaných MMO) a zápis do GLB (glTF 2.0) s více materiály,
volitelně s kostrou a animacemi. Bez závislostí kromě numpy.
"""
import json
import math
import struct

import numpy as np


# ------------------------------------------------------------------ šum
def _hash3(ix, iy, iz, seed):
    h = (ix * 374761393 + iy * 668265263 + iz * 1274126177 + seed * 974634211) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFFFF) / float(0xFFFFFF)


def noise3(P, scale=1.0, seed=0):
    """Hodnotový šum 0..1 v bodech P (N,3)."""
    Q = np.asarray(P, np.float64) * scale
    i = np.floor(Q).astype(np.int64)
    f = Q - i
    u = f * f * (3 - 2 * f)
    out = np.zeros(len(Q))
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                h = _hash3(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
                w = (u[:, 0] if dx else 1 - u[:, 0]) * (u[:, 1] if dy else 1 - u[:, 1]) * (u[:, 2] if dz else 1 - u[:, 2])
                out += h * w
    return out


def fbm(P, scale=1.0, octaves=3, seed=0):
    total, amp, norm = np.zeros(len(P)), 1.0, 0.0
    for o in range(octaves):
        total += amp * noise3(P, scale * (2 ** o), seed + o * 17)
        norm += amp
        amp *= 0.5
    return total / norm


# ------------------------------------------------------------------ síť
class Mesh:
    def __init__(self, P=None, I=None, C=None, B=None):
        self.P = np.zeros((0, 3), np.float32) if P is None else np.asarray(P, np.float32)
        self.I = np.zeros((0, 3), np.int64) if I is None else np.asarray(I, np.int64)
        n = len(self.P)
        self.C = np.ones((n, 4), np.float32) if C is None else np.asarray(C, np.float32)
        self.B = np.zeros(n, np.int64) if B is None else np.asarray(B, np.int64)   # kost (tuhé díly)
        self.N = None
        self.UV = None     # vlastní UV (N, 2) – jinak promítnutí ze tří stran (box mapping)
        self.flat = False

    def copy(self):
        m = Mesh(self.P.copy(), self.I.copy(), self.C.copy(), self.B.copy())
        m.flat = self.flat
        return m

    # transformace ----------------------------------------------------------
    def translate(self, x, y=0.0, z=0.0):
        self.P = self.P + np.array([x, y, z], np.float32)
        return self

    def scale(self, sx, sy=None, sz=None):
        sy = sx if sy is None else sy
        sz = sx if sz is None else sz
        self.P = self.P * np.array([sx, sy, sz], np.float32)
        return self

    def rotate(self, rx=0.0, ry=0.0, rz=0.0):
        """Stupně, pořadí X, Y, Z."""
        self.P = self.P @ rot_matrix(rx, ry, rz).T
        return self

    def apply(self, fn):
        self.P = np.asarray(fn(self.P), np.float32)
        return self

    def bone(self, index):
        self.B = np.full(len(self.P), index, np.int64)
        return self

    # barvy -----------------------------------------------------------------
    def color(self, rgb):
        self.C[:, :3] = np.asarray(rgb, np.float32)[None, :]
        return self

    def paint(self, fn):
        """fn(P, N) -> barvy (N,3)."""
        N = self.normals()
        self.C[:, :3] = np.clip(np.asarray(fn(self.P, N), np.float32), 0, 4)
        return self

    def gradient(self, bottom, top, y0=None, y1=None, axis=1):
        v = self.P[:, axis]
        a = v.min() if y0 is None else y0
        b = v.max() if y1 is None else y1
        t = np.clip((v - a) / max(b - a, 1e-6), 0, 1)[:, None]
        self.C[:, :3] = np.asarray(bottom, np.float32) * (1 - t) + np.asarray(top, np.float32) * t
        return self

    def mottle(self, amount=0.12, scale=3.0, seed=0):
        """Malířská nerovnoměrnost barvy."""
        n = fbm(self.P, scale, 3, seed)[:, None]
        self.C[:, :3] *= (1 - amount) + 2 * amount * n
        return self

    def shade_ao(self, strength=0.35, y_ref=None):
        """Jednoduché zastínění: spodky a místa u země tmavší (malovaný vzhled)."""
        N = self.normals()
        down = np.clip(-N[:, 1], 0, 1)
        k = 1 - strength * (0.5 * down + 0.5 * (1 - np.clip((self.P[:, 1] - (self.P[:, 1].min() if y_ref is None else y_ref)) /
                                                         max(np.ptp(self.P[:, 1]), 1e-6) * 2.5, 0, 1)))
        self.C[:, :3] *= k[:, None]
        return self

    def top_light(self, strength=0.25):
        """Horní plochy světlejší (nasvícení shora namalované do barvy)."""
        N = self.normals()
        self.C[:, :3] *= (1 + strength * np.clip(N[:, 1], 0, 1))[:, None]
        return self

    # normály -----------------------------------------------------------------
    def normals(self):
        if self.N is not None and len(self.N) == len(self.P):
            return self.N
        P, I = self.P.astype(np.float64), self.I
        fn = np.cross(P[I[:, 1]] - P[I[:, 0]], P[I[:, 2]] - P[I[:, 0]])
        # vyhlazení přes vrcholy se stejnou polohou (švy)
        _, weld = np.unique(np.round(P, 4), axis=0, return_inverse=True)
        weld = weld.reshape(-1)
        acc = np.zeros((weld.max() + 1, 3))
        for k in range(3):
            np.add.at(acc, weld[I[:, k]], fn)
        Nv = acc[weld]
        L = np.linalg.norm(Nv, axis=1, keepdims=True)
        Nv = Nv / np.maximum(L, 1e-12)
        Nv[L[:, 0] < 1e-12] = [0, 1, 0]
        self.N = Nv.astype(np.float32)
        return self.N

    def invalidate(self):
        self.N = None
        return self


def rot_matrix(rx, ry, rz):
    a, b, c = math.radians(rx), math.radians(ry), math.radians(rz)
    X = np.array([[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]])
    Y = np.array([[math.cos(b), 0, math.sin(b)], [0, 1, 0], [-math.sin(b), 0, math.cos(b)]])
    Z = np.array([[math.cos(c), -math.sin(c), 0], [math.sin(c), math.cos(c), 0], [0, 0, 1]])
    return (Z @ Y @ X).astype(np.float32)


def merge(*meshes):
    ms = [m for m in meshes if m is not None and len(m.P)]
    if not ms:
        return Mesh()
    P, I, C, B, off = [], [], [], [], 0
    for m in ms:
        P.append(m.P)
        I.append(m.I + off)
        C.append(m.C)
        B.append(m.B)
        off += len(m.P)
    out = Mesh(np.concatenate(P), np.concatenate(I), np.concatenate(C), np.concatenate(B))
    if all(m.N is not None for m in ms):
        out.N = np.concatenate([m.N for m in ms])
    if all(m.UV is not None for m in ms):
        out.UV = np.concatenate([m.UV for m in ms]).astype(np.float32)
    return out


# ------------------------------------------------------------------ tvary
def lathe(profile, seg=16, cap_bottom=True, cap_top=True, phase=0.0):
    """Rotační těleso z profilu [(poloměr, y), ...] zdola nahoru (kolem osy Y)."""
    prof = np.asarray(profile, np.float32)
    rings = len(prof)
    ang = np.linspace(0, 2 * math.pi, seg, endpoint=False) + phase
    P = []
    for r, y in prof:
        for a in ang:
            P.append([r * math.cos(a), y, r * math.sin(a)])
    I = []
    for j in range(rings - 1):
        for i in range(seg):
            a = j * seg + i
            b = j * seg + (i + 1) % seg
            c = (j + 1) * seg + i
            d = (j + 1) * seg + (i + 1) % seg
            I += [[a, c, b], [b, c, d]]
    P = list(P)
    if cap_bottom and prof[0][0] > 1e-5:
        ci = len(P)
        P.append([0, prof[0][1], 0])
        for i in range(seg):
            I.append([ci, i, (i + 1) % seg])
    if cap_top and prof[-1][0] > 1e-5:
        ci = len(P)
        P.append([0, prof[-1][1], 0])
        base = (rings - 1) * seg
        for i in range(seg):
            I.append([ci, base + (i + 1) % seg, base + i])
    return Mesh(np.array(P, np.float32), np.array(I))


def cylinder(r0, r1, h, seg=12, caps=True):
    return lathe([(r0, 0), (r1, h)], seg, caps, caps)


def cone(r, h, seg=12):
    return lathe([(r, 0), (1e-6, h)], seg, True, False)


def sphere(r=1.0, seg=16, rings=10):
    prof = [(r * math.sin(math.pi * k / rings), -r * math.cos(math.pi * k / rings)) for k in range(rings + 1)]
    prof[0] = (1e-6, -r)
    prof[-1] = (1e-6, r)
    return lathe(prof, seg, False, False)


def capsule(r, h, seg=12, rings=4):
    """Kapsle podél Y od 0 do h (h včetně polokoulí)."""
    prof = []
    for k in range(rings + 1):
        a = -math.pi / 2 + math.pi / 2 * k / rings
        prof.append((max(r * math.cos(a), 1e-6), r + r * math.sin(a)))
    for k in range(rings + 1):
        a = math.pi / 2 * k / rings
        prof.append((max(r * math.cos(a), 1e-6), h - r + r * math.sin(a)))
    return lathe(prof, seg, False, False)


def box(sx, sy, sz, center=(0, 0, 0), bevel=0.0):
    """Kvádr (bevel > 0 = zkosené hrany: 8 rohů + hrany jako osmistěn)."""
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    if bevel <= 0:
        P, I = [], []
        faces = [((1, 0, 0), (0, 1, 0), (0, 0, 1)), ((-1, 0, 0), (0, 1, 0), (0, 0, -1)), ((0, 1, 0), (0, 0, 1), (1, 0, 0)),
                 ((0, -1, 0), (0, 0, -1), (1, 0, 0)), ((0, 0, 1), (1, 0, 0), (0, 1, 0)), ((0, 0, -1), (-1, 0, 0), (0, 1, 0))]
        h = np.array([hx, hy, hz])
        for n, u, v in faces:
            n, u, v = np.array(n), np.array(u), np.array(v)
            base = len(P)
            for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                P.append((n + u * su + v * sv) * h)
            I += [[base, base + 1, base + 2], [base, base + 2, base + 3]]
        m = Mesh(np.array(P, np.float32), np.array(I))
        m.flat = True
    else:
        m = rounded_box(sx, sy, sz, bevel)
    return m.translate(*center)


def rounded_box(sx, sy, sz, r, seg=3):
    """Kvádr se zaoblenými hranami (koule natažená na kvádr)."""
    s = sphere(1.0, seg * 4, seg * 2)
    P = s.P.copy()
    inner = np.array([sx / 2 - r, sy / 2 - r, sz / 2 - r], np.float32)
    P = np.sign(P) * inner + P * r
    s.P = P
    return s


def plane(sx, sz, nx=1, nz=1):
    xs = np.linspace(-sx / 2, sx / 2, nx + 1)
    zs = np.linspace(-sz / 2, sz / 2, nz + 1)
    P = np.array([[x, 0, z] for z in zs for x in xs], np.float32)
    I = []
    for j in range(nz):
        for i in range(nx):
            a = j * (nx + 1) + i
            I += [[a, a + nx + 1, a + 1], [a + 1, a + nx + 1, a + nx + 2]]
    return Mesh(P, np.array(I))


def double_sided(m):
    """Plocha viditelná z obou stran (listy, látka)."""
    back = m.copy()
    back.I = back.I[:, ::-1]
    return merge(m, back)


def outline(m, thickness=0.03, color=(0.02, 0.02, 0.05)):
    """Obrys v kresleném stylu (inverted hull): kopie sítě nafouknutá podél normál s obráceným pořadím vrcholů.
    S ořezem odvrácených stěn je vidět jen její vnitřek za okrajem siluety = černá linka kolem modelu."""
    o = m.copy()
    o.flat = False
    N = m.copy().normals() if not m.flat else m.normals()
    # svařené normály (i u plošně stínovaných dílů), ať se slupka na hranách neroztrhne
    P = m.P.astype(np.float64)
    _, weld = np.unique(np.round(P, 4), axis=0, return_inverse=True)
    weld = weld.reshape(-1)
    acc = np.zeros((weld.max() + 1, 3))
    np.add.at(acc, weld, N)
    Nw = acc[weld]
    Nw /= np.maximum(np.linalg.norm(Nw, axis=1, keepdims=True), 1e-9)
    o.P = (m.P + Nw * thickness).astype(np.float32)
    o.I = m.I[:, ::-1].copy()
    o.C = np.tile(np.array(list(color) + [1.0], np.float32), (len(o.P), 1))
    o.N = None
    return o


def displace(m, amount, scale=1.0, seed=0, along_normal=True):
    N = m.normals()
    n = (fbm(m.P, scale, 3, seed) - 0.5) * 2 * amount
    m.P = m.P + (N * n[:, None] if along_normal else np.array([0, 1, 0]) * n[:, None])
    m.invalidate()
    return m


def crystal(h, r, sides=6, tip=0.35, seed=0):
    """Krystal: hranol se špičkou, lehce nepravidelný."""
    rng = np.random.default_rng(seed)
    rr = r * (0.85 + 0.3 * rng.random())
    prof = [(rr * 0.75, 0), (rr, h * 0.12), (rr * 0.92, h * (1 - tip)), (1e-5, h)]
    m = lathe(prof, sides, True, False, phase=rng.random())
    m.flat = True
    return m


# ------------------------------------------------------------------ GLB
class _Bin:
    def __init__(self):
        self.data = bytearray()
        self.views = []
        self.accs = []

    def view(self, raw, target=None):
        while len(self.data) % 4:
            self.data += b"\0"
        v = {"buffer": 0, "byteOffset": len(self.data), "byteLength": len(raw)}
        if target:
            v["target"] = target
        self.data += raw
        self.views.append(v)
        return len(self.views) - 1

    def acc(self, arr, ctype, typ, target=None, minmax=False):
        arr = np.ascontiguousarray(arr)
        a = {"bufferView": self.view(arr.tobytes(), target), "componentType": ctype, "count": int(arr.shape[0]), "type": typ}
        if minmax:
            flat = arr.reshape(arr.shape[0], -1)
            a["min"] = [float(v) for v in flat.min(0)]
            a["max"] = [float(v) for v in flat.max(0)]
        self.accs.append(a)
        return len(self.accs) - 1


def _expand_flat(m):
    """Plošné stínování: každý trojúhelník vlastní vrcholy."""
    P = m.P[m.I.reshape(-1)]
    C = m.C[m.I.reshape(-1)]
    B = m.B[m.I.reshape(-1)]
    I = np.arange(len(P)).reshape(-1, 3)
    fn = np.cross(P[I[:, 1]] - P[I[:, 0]], P[I[:, 2]] - P[I[:, 0]])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    out = Mesh(P, I, C, B)
    out.N = np.repeat(fn, 3, axis=0).astype(np.float32)
    return out


def _box_uv(P, N, scale):
    """UV promítnutím ze tří stran podle převládající osy normály (box mapping), `scale` = metrů na dlaždici."""
    a = np.argmax(np.abs(N), axis=1)
    uv = np.where((a == 0)[:, None], P[:, [2, 1]], np.where((a == 1)[:, None], P[:, [0, 2]], P[:, [0, 1]]))
    uv = uv / float(scale)
    uv[:, 1] = -uv[:, 1]   # obrázek má řádky shora dolů: +Y modelu = nahoru v textuře
    return uv.astype(np.float32)


def _relative_tint(C):
    """Barvy vrcholů jako odstín k textuře: nejsvětlejší místa = plná textura, tmavší = stín / nádech."""
    ref = np.percentile(C[:, :3], 95, axis=0)
    out = C.copy()
    out[:, :3] = np.clip(C[:, :3] / np.maximum(ref, 1e-3), 0, 1)
    return out


def write_glb(path, parts, skeleton=None, animations=None, name="Model"):
    """parts: [(Mesh, materiál dict)]; materiál: color, roughness, metallic, emissive, emissive_strength, double,
    texture (cesta k .jpg/.png, vloží se do .glb; UV promítnutím ze tří stran), uv_scale (m na dlaždici),
    normal (normálová mapa), orm (glTF occlusion/roughness/metallic mapa).
    skeleton: [(jméno, rodič|None, (x, y, z) svět)] – pak se zapíše skin (váha 1 na kost Mesh.B).
    animations: [(jméno, délka, smyčka, fn(t) -> {kost: (rx, ry, rz)}, translace pánve fn(t)->(dx,dy,dz))]."""
    out = _Bin()
    materials, primitives = [], []
    images, image_index = [], {}

    def image(file):
        if file not in image_index:
            with open(file, "rb") as f:
                raw = f.read()
            mime = "image/png" if file.lower().endswith(".png") else "image/jpeg"
            images.append({"bufferView": out.view(raw), "mimeType": mime})
            image_index[file] = len(images) - 1
        return image_index[file]
    skinned = skeleton is not None
    for mesh, mat in parts:
        if not len(mesh.P):
            continue
        m = _expand_flat(mesh) if mesh.flat else mesh
        N = m.normals()
        axisN = N
        own_uv = mesh.UV is not None and not mesh.flat
        if mat.get("texture") and not mesh.flat and not own_uv:
            # každá stěna vlastní vrcholy (jedna osa promítnutí na stěnu), hladké normály zůstanou
            I = m.I.reshape(-1)
            fn = np.cross(m.P[m.I[:, 1]] - m.P[m.I[:, 0]], m.P[m.I[:, 2]] - m.P[m.I[:, 0]])
            e = Mesh(m.P[I], np.arange(len(I)).reshape(-1, 3), m.C[I], m.B[I])
            e.N = N[I]
            m, N, axisN = e, e.N, np.repeat(fn, 3, axis=0)
        attrs = {
            "POSITION": out.acc(m.P.astype(np.float32), 5126, "VEC3", 34962, minmax=True),
            "NORMAL": out.acc(N.astype(np.float32), 5126, "VEC3", 34962),
            "COLOR_0": out.acc(np.clip(_relative_tint(m.C) if mat.get("texture") else m.C, 0, 1).astype(np.float32),
                               5126, "VEC4", 34962),
        }
        if mat.get("texture") and own_uv:
            attrs["TEXCOORD_0"] = out.acc(np.ascontiguousarray(m.UV, np.float32), 5126, "VEC2", 34962)
        elif mat.get("texture"):
            uv = _box_uv(m.P, axisN, mat.get("uv_scale", 1.0))
            if mat.get("uv_swap"):   # otočení textury o 90° (např. řady tašek podél hřebene střechy)
                uv = np.ascontiguousarray(uv[:, ::-1])
            attrs["TEXCOORD_0"] = out.acc(uv, 5126, "VEC2", 34962)
        if skinned:
            J = np.zeros((len(m.P), 4), np.uint16)
            J[:, 0] = m.B
            W = np.zeros((len(m.P), 4), np.float32)
            W[:, 0] = 1
            attrs["JOINTS_0"] = out.acc(J, 5123, "VEC4", 34962)
            attrs["WEIGHTS_0"] = out.acc(W, 5126, "VEC4", 34962)
        ind = out.acc(m.I.reshape(-1).astype(np.uint32), 5125, "SCALAR", 34963)
        pbr = {"baseColorFactor": list(mat.get("color", (1, 1, 1))) + [1.0],
               "roughnessFactor": float(mat.get("roughness", 0.85)), "metallicFactor": float(mat.get("metallic", 0.0))}
        material = {"name": mat.get("name", "m%d" % len(materials)), "pbrMetallicRoughness": pbr}
        if mat.get("texture"):
            pbr["baseColorTexture"] = {"index": image(mat["texture"])}
            if mat.get("normal"):
                material["normalTexture"] = {"index": image(mat["normal"])}
            if mat.get("orm"):
                orm_index = image(mat["orm"])
                pbr["metallicRoughnessTexture"] = {"index": orm_index}
                material["occlusionTexture"] = {"index": orm_index}
        if mat.get("emissive"):
            material["emissiveFactor"] = list(mat["emissive"])
            if mat.get("emissive_strength", 1.0) != 1.0:
                material["extensions"] = {"KHR_materials_emissive_strength": {"emissiveStrength": float(mat["emissive_strength"])}}
        if mat.get("double"):
            material["doubleSided"] = True
        if mat.get("alpha_cutoff"):   # výřez průhlednosti (listí, tráva): alfa z textury barvy
            material["alphaMode"] = "MASK"
            material["alphaCutoff"] = float(mat["alpha_cutoff"])
        materials.append(material)
        primitives.append({"attributes": attrs, "indices": ind, "material": len(materials) - 1, "mode": 4})

    nodes = [{"name": name, "mesh": 0}]
    gltf = {"asset": {"version": "2.0", "generator": "Eryndor meshkit"}, "scene": 0, "scenes": [{"nodes": [0]}],
            "nodes": nodes, "meshes": [{"name": name, "primitives": primitives}], "materials": materials}
    if images:
        # textury = obrázky 1:1 (index textury = index obrázku), opakování dlaždic
        gltf["images"] = images
        gltf["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
        gltf["textures"] = [{"sampler": 0, "source": i} for i in range(len(images))]
    if any("extensions" in m for m in materials):
        gltf["extensionsUsed"] = ["KHR_materials_emissive_strength"]
    if skinned:
        names = [b[0] for b in skeleton]
        world = {b[0]: np.array(b[2], np.float32) for b in skeleton}
        nodes[0]["skin"] = 0
        ibm = np.zeros((len(names), 16), np.float32)
        for i, n in enumerate(names):
            mm = np.eye(4, dtype=np.float32)
            mm[:3, 3] = -world[n]
            ibm[i] = mm.T.reshape(-1)
        for n, parent, _ in skeleton:
            local = world[n] - (world[parent] if parent else 0)
            nodes.append({"name": n, "translation": [float(v) for v in local]})
        for i, (n, parent, _) in enumerate(skeleton):
            if parent:
                nodes[names.index(parent) + 1].setdefault("children", []).append(i + 1)
        root = names.index(skeleton[0][0]) + 1
        gltf["scenes"][0]["nodes"] = [0, root]
        gltf["skins"] = [{"inverseBindMatrices": out.acc(ibm, 5126, "MAT4"), "joints": list(range(1, len(names) + 1)),
                          "skeleton": root}]
        anims = []
        for aname, dur, loop, fn, tfn in (animations or []):
            nf = max(2, int(round(dur * 30)) + 1)
            times = np.linspace(0, dur, nf).astype(np.float32)
            tacc = out.acc(times.reshape(-1, 1), 5126, "SCALAR", minmax=True)
            rots = {n: np.zeros((nf, 4), np.float32) for n in names}
            trans = np.zeros((nf, 3), np.float32)
            hips = skeleton[1][0] if len(skeleton) > 1 else names[0]
            base = world[hips] - (world[skeleton[1][1]] if skeleton[1][1] else 0)
            for k, t in enumerate(times):
                tt = float(t) if not loop or k < nf - 1 else 0.0
                R = fn(tt)
                for n in names:
                    rots[n][k] = quat_euler(*R.get(n, (0, 0, 0)))
                d = tfn(tt) if tfn else (0, 0, 0)
                trans[k] = base + np.array(d, np.float32)
            samplers, channels = [], []
            for i, n in enumerate(names):
                if not np.allclose(rots[n], [0, 0, 0, 1]):
                    samplers.append({"input": tacc, "output": out.acc(rots[n], 5126, "VEC4"), "interpolation": "LINEAR"})
                    channels.append({"sampler": len(samplers) - 1, "target": {"node": i + 1, "path": "rotation"}})
            samplers.append({"input": tacc, "output": out.acc(trans, 5126, "VEC3"), "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": names.index(hips) + 1, "path": "translation"}})
            anims.append({"name": aname, "samplers": samplers, "channels": channels})
        if anims:
            gltf["animations"] = anims
    gltf["accessors"] = out.accs
    gltf["bufferViews"] = out.views
    gltf["buffers"] = [{"byteLength": len(out.data)}]
    js = json.dumps(gltf, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    while len(out.data) % 4:
        out.data += b"\0"
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(out.data)))
        f.write(struct.pack("<I4s", len(js), b"JSON"))
        f.write(js)
        f.write(struct.pack("<I4s", len(out.data), b"BIN\0"))
        f.write(out.data)


def quat_euler(xd, yd, zd):
    hx, hy, hz = math.radians(xd) / 2, math.radians(yd) / 2, math.radians(zd) / 2
    qx = np.array([math.sin(hx), 0, 0, math.cos(hx)])
    qy = np.array([0, math.sin(hy), 0, math.cos(hy)])
    qz = np.array([0, 0, math.sin(hz), math.cos(hz)])

    def mul(a, b):
        ax, ay, az, aw = a
        bx, by, bz, bw = b
        return np.array([aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
                         aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz])
    return mul(qz, mul(qy, qx))
