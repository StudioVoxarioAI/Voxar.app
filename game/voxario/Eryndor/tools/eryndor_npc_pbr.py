#!/usr/bin/env python3
"""Fotorealistické materiály brnění a oblečení NPC (MakeHuman, Models/humans) z fotoskenů Poly Haven (CC0).

  python3 tools/eryndor_npc_pbr.py [--cache <složka>] [--size 1024]

Díly brnění a oděvu z tools/mh_build.py jsou bez UV a mají jen barvu vrcholů (ocel, zlato, kůže, látka).
Nástroj jim dá:
  * UV promítnutím ze tří stran po trojúhelnících (velikost dlaždice ve skutečných metrech),
  * detailní texturu fotoskenu (odbarvenou a normalizovanou – barvu dál určuje návrh postavy přes barvu vrcholů),
  * normálovou mapu (OpenGL) a ORM mapu (okluze, drsnost, kovovost: ocel a zlato kovové).
Textury se uloží do Assets/Textures/npc/pbr a vloží do .glb. Kůže, oči, vlasy (MakeHuman) zůstávají.
"""
from __future__ import annotations

import argparse
import io
import json
import os
import pathlib
import struct
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from terrain_pbr import fetch  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
HUMANS = HERE.parent / "Assets" / "Models" / "humans"
OUT = HERE.parent / "Assets" / "Textures" / "npc" / "pbr"
MAPS = {"albedo": "Diffuse", "normal": "nor_gl", "arm": "arm"}

# materiál dílu -> (fotosken, dlaždice v m, kovovost, násobek drsnosti, síla detailu barvy, zesílení normály)
KINDS = {
    "steel": ("metal_plate_02", 0.5, 1.0, 0.78, 0.55, 1.7),    # tepané pláty: škrábance, nerovnosti, matnější
    "gold": ("metal_plate_02", 0.35, 1.0, 0.6, 0.4, 1.3),      # zlacené lemy a ozdoby (barvu dává návrh)
    "leather": ("brown_leather", 0.3, 0.0, 1.0, 0.8, 1.4),     # kůže: póry, švy, ohyby
    "cloth": ("rough_linen", 0.12, 0.0, 1.0, 0.75, 1.8),        # hrubé plátno / vlna: vazba, chlupy, nerovnosti
}


# ------------------------------------------------------------------ glTF
def load_glb(path):
    d = path.read_bytes()
    n = struct.unpack("<I", d[12:16])[0]
    j = json.loads(d[20:20 + n])
    rest = d[20 + n:]
    bn = struct.unpack("<I", rest[:4])[0]
    return j, bytearray(rest[8:8 + bn])


def save_glb(path, j, b):
    while len(b) % 4:
        b += b"\0"
    j["buffers"] = [{"byteLength": len(b)}]
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(b)))
        f.write(struct.pack("<I4s", len(js), b"JSON"))
        f.write(js)
        f.write(struct.pack("<I4s", len(b), b"BIN\0"))
        f.write(b)


DT = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read(j, b, i):
    a = j["accessors"][i]
    v = j["bufferViews"][a["bufferView"]]
    dt = DT[a["componentType"]]
    n = NC[a["type"]]
    o = v.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = v.get("byteStride", 0)
    item = n * np.dtype(dt).itemsize
    if stride and stride != item:
        raw = np.frombuffer(bytes(b[o:o + stride * a["count"]]), np.uint8).reshape(-1, stride)[:, :item]
        return raw.copy().view(dt).reshape(a["count"], n)
    return np.frombuffer(bytes(b[o:o + item * a["count"]]), dt).reshape(a["count"], n).copy()


def write(j, b, arr, comp, typ, minmax=False, target=None, normalized=False):
    while len(b) % 4:
        b += b"\0"
    data = np.ascontiguousarray(arr, DT[comp])
    off = len(b)
    b += data.tobytes()
    bv = {"buffer": 0, "byteOffset": off, "byteLength": data.nbytes}
    if target:
        bv["target"] = target
    j["bufferViews"].append(bv)
    acc = {"bufferView": len(j["bufferViews"]) - 1, "componentType": comp, "count": int(data.shape[0]), "type": typ}
    if normalized:
        acc["normalized"] = True
    if minmax:
        acc["min"] = [float(x) for x in data.reshape(data.shape[0], -1).min(0)]
        acc["max"] = [float(x) for x in data.reshape(data.shape[0], -1).max(0)]
    j["accessors"].append(acc)
    return len(j["accessors"]) - 1


def add_image(j, b, data, mime, name):
    while len(b) % 4:
        b += b"\0"
    off = len(b)
    b += data
    j["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": len(data)})
    j.setdefault("images", []).append({"bufferView": len(j["bufferViews"]) - 1, "mimeType": mime, "name": name})
    if not j.get("samplers"):
        j["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
    j.setdefault("textures", []).append({"source": len(j["images"]) - 1, "sampler": 0})
    return len(j["textures"]) - 1


# ------------------------------------------------------------------ textury
def build_maps(kind, cache, size):
    asset, _, metal, rough_mul, detail, nboost = KINDS[kind]
    p = fetch(asset, cache, MAPS)
    if "albedo" not in p:   # některé látky mají barevné varianty (col_01…) místo Diffuse
        p.update(fetch(asset, cache, {"albedo": "col_01"}))
    OUT.mkdir(parents=True, exist_ok=True)
    alb = np.asarray(Image.open(p["albedo"]).convert("RGB").resize((size, size), Image.LANCZOS), np.float32) / 255
    lum = alb @ np.array([0.299, 0.587, 0.114])
    # detail: odbarvený jas kolem 1 (barva z návrhu), síla podle druhu
    det = lum / max(np.median(lum), 1e-3)
    det = 1.0 + (det - 1.0) * detail
    base = np.clip(det * 0.82, 0, 1)
    base_img = Image.fromarray((np.repeat(base[..., None], 3, 2) * 255 + 0.5).astype(np.uint8), "RGB")
    nrm = np.asarray(Image.open(p["normal"]).convert("RGB").resize((size, size), Image.LANCZOS), np.float32) / 127.5 - 1.0
    nrm[..., :2] *= nboost                                          # výraznější reliéf (tepání, vazba látky)
    nrm /= np.maximum(np.linalg.norm(nrm, axis=2, keepdims=True), 1e-6)
    nrm_img = Image.fromarray(((nrm * 0.5 + 0.5) * 255 + 0.5).clip(0, 255).astype(np.uint8), "RGB")
    arm = np.asarray(Image.open(p["arm"]).convert("RGB").resize((size, size), Image.LANCZOS), np.float32) / 255
    orm = np.zeros_like(arm)
    orm[..., 0] = 0.55 + 0.45 * arm[..., 0]                         # okluze (jemně)
    orm[..., 1] = np.clip(0.18 + arm[..., 1] * rough_mul, 0.25, 1.0) if metal > 0 else np.clip(arm[..., 1] * rough_mul, 0.08, 1.0)
    orm[..., 2] = metal                                             # kovovost
    orm_img = Image.fromarray((orm * 255 + 0.5).astype(np.uint8), "RGB")
    out = {}
    for key, img, q in (("basecolor", base_img, 90), ("normal", nrm_img, 95), ("orm", orm_img, 92)):
        path = OUT / f"{kind}_{key}.jpg"
        img.save(path, quality=q, optimize=True)
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=q)
        out[key] = buf.getvalue()
    return out


# ------------------------------------------------------------------ UV a materiály
def box_uv(P, N, tile):
    a = np.argmax(np.abs(N), axis=1)
    uv = np.where((a == 0)[:, None], P[:, [2, 1]], np.where((a == 1)[:, None], P[:, [0, 2]], P[:, [0, 1]]))
    uv = uv / tile
    uv[:, 1] = -uv[:, 1]
    return uv.astype(np.float32)


def process(path, maps):
    j, b = load_glb(path)
    mats = j["materials"]
    kind_mat = {}
    changed = 0
    for mesh in j["meshes"]:
        for prim in mesh["primitives"]:
            name = mats[prim["material"]].get("name", "")
            if name not in KINDS or "TEXCOORD_0" in prim["attributes"] or "indices" not in prim:
                continue
            at = prim["attributes"]
            idx = read(j, b, prim["indices"]).reshape(-1)
            cols = {k: read(j, b, v) for k, v in at.items()}
            # každý trojúhelník vlastní vrcholy (jedna osa promítnutí na trojúhelník – bez protažení na švech)
            ex = {k: v[idx] for k, v in cols.items()}
            P = ex["POSITION"].astype(np.float64)
            tri = P.reshape(-1, 3, 3)
            fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
            fn = np.repeat(fn, 3, axis=0)
            uv = box_uv(P, fn, KINDS[name][1])
            new = {}
            for k, v in ex.items():
                a = j["accessors"][at[k]]
                comp = a["componentType"]
                new[k] = write(j, b, v, comp, a["type"], minmax=(k == "POSITION"), normalized=a.get("normalized", False))
            new["TEXCOORD_0"] = write(j, b, uv, 5126, "VEC2")
            prim["attributes"] = new
            prim["indices"] = write(j, b, np.arange(len(P), dtype=np.uint32), 5125, "SCALAR")
            if name not in kind_mat:
                m = maps[name]
                tb = add_image(j, b, m["basecolor"], "image/jpeg", name + "_basecolor")
                tn = add_image(j, b, m["normal"], "image/jpeg", name + "_normal")
                to = add_image(j, b, m["orm"], "image/jpeg", name + "_orm")
                old = mats[prim["material"]]
                pbr = old.get("pbrMetallicRoughness", {})
                mat = {"name": name + " pbr",
                       "pbrMetallicRoughness": {"baseColorTexture": {"index": tb}, "metallicRoughnessTexture": {"index": to},
                                                "baseColorFactor": pbr.get("baseColorFactor", [1, 1, 1, 1]),
                                                "metallicFactor": 1.0, "roughnessFactor": 1.0},
                       "normalTexture": {"index": tn}, "occlusionTexture": {"index": to}}
                if "emissiveFactor" in old:
                    mat["emissiveFactor"] = old["emissiveFactor"]
                mats.append(mat)
                kind_mat[name] = len(mats) - 1
            prim["material"] = kind_mat[name]
            changed += 1
    if changed:
        save_glb(path, j, compact(j, b))
    return changed


def compact(j, b):
    """Zahodí nepoužité accessory / bufferView a složí buffer znovu."""
    used_acc = set()
    for mesh in j["meshes"]:
        for p in mesh["primitives"]:
            used_acc.update(p["attributes"].values())
            if "indices" in p:
                used_acc.add(p["indices"])
            for t in p.get("targets", []):
                used_acc.update(t.values())
    for s in j.get("skins", []):
        if "inverseBindMatrices" in s:
            used_acc.add(s["inverseBindMatrices"])
    for an in j.get("animations", []):
        for s in an["samplers"]:
            used_acc.update((s["input"], s["output"]))
    acc_map, accs = {}, []
    for i, a in enumerate(j["accessors"]):
        if i in used_acc:
            acc_map[i] = len(accs)
            accs.append(a)
    used_bv = {a["bufferView"] for a in accs if "bufferView" in a} | {im["bufferView"] for im in j.get("images", []) if "bufferView" in im}
    nb = bytearray()
    bv_map, bvs = {}, []
    for i, v in enumerate(j["bufferViews"]):
        if i not in used_bv:
            continue
        while len(nb) % 4:
            nb += b"\0"
        o = v.get("byteOffset", 0)
        data = b[o:o + v["byteLength"]]
        nv = dict(v)
        nv["byteOffset"] = len(nb)
        nb += data
        bv_map[i] = len(bvs)
        bvs.append(nv)
    for a in accs:
        if "bufferView" in a:
            a["bufferView"] = bv_map[a["bufferView"]]
    for im in j.get("images", []):
        if "bufferView" in im:
            im["bufferView"] = bv_map[im["bufferView"]]
    j["accessors"], j["bufferViews"] = accs, bvs
    def remap(o):
        if isinstance(o, dict):
            return {k: remap(v) for k, v in o.items()}
        return o
    for mesh in j["meshes"]:
        for p in mesh["primitives"]:
            p["attributes"] = {k: acc_map[v] for k, v in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = acc_map[p["indices"]]
            if "targets" in p:
                p["targets"] = [{k: acc_map[v] for k, v in t.items()} for t in p["targets"]]
    for s in j.get("skins", []):
        if "inverseBindMatrices" in s:
            s["inverseBindMatrices"] = acc_map[s["inverseBindMatrices"]]
    for an in j.get("animations", []):
        for s in an["samplers"]:
            s["input"], s["output"] = acc_map[s["input"]], acc_map[s["output"]]
    return nb


def skin_maps(size=2048, seed=3):
    """Mikroreliéf kůže (póry, jemné vrásky) a proměnlivá drsnost – procedurálně, dlaždice přes UV kůže."""
    rng = np.random.default_rng(seed)
    h = np.zeros((size, size), np.float32)
    for k, amp in ((size // 2, 0.5), (size // 4, 0.8), (size // 16, 0.35)):
        g = rng.random((k, k)).astype(np.float32)
        h += amp * np.asarray(Image.fromarray((g * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC), np.float32) / 255
    pores = rng.random((size, size)) < 0.012                       # póry: drobné prohlubně
    pm = np.asarray(Image.fromarray((pores * 255).astype(np.uint8)).filter(__import__("PIL.ImageFilter", fromlist=["x"]).GaussianBlur(1.2)), np.float32) / 255
    h -= pm * 1.6
    gy, gx = np.gradient(h)
    n = np.dstack([-gx * 0.42, -gy * 0.42, np.ones_like(h)])   # jemné: póry vidět jen zblízka
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    nimg = Image.fromarray(((n * 0.5 + 0.5) * 255 + 0.5).astype(np.uint8), "RGB")
    orm = np.zeros((size, size, 3), np.float32)
    orm[..., 0] = 1.0 - 0.25 * pm
    orm[..., 1] = np.clip(0.5 + 0.12 * (h - h.mean()) / (h.std() + 1e-6) * 0.5 + 0.1 * pm, 0.35, 0.75)
    oimg = Image.fromarray((orm * 255 + 0.5).astype(np.uint8), "RGB")
    out = {}
    for key, img in (("normal", nimg), ("orm", oimg)):
        img.save(OUT / f"skin_{key}.jpg", quality=92)
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=92)
        out[key] = buf.getvalue()
    return out


def refine(path, maps, skin):
    """Už upravený model: nové mapy materiálů, realistické barvy kovů a látek (barvy vrcholů), mikroreliéf kůže."""
    j, b = load_glb(path)
    mats = j["materials"]
    tex_img = lambda ti: j["textures"][ti]["source"]
    def replace_image(ti, data):
        while len(b) % 4:
            b.extend(b"\0")
        off = len(b)
        b.extend(data)
        j["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": len(data)})
        j["images"][tex_img(ti)]["bufferView"] = len(j["bufferViews"]) - 1
        j["images"][tex_img(ti)]["mimeType"] = "image/jpeg"
    done = set()
    for mi, m in enumerate(mats):
        name = m.get("name", "")
        kind = name[:-4] if name.endswith(" pbr") else None
        if kind in maps and mi not in done:
            pbr = m["pbrMetallicRoughness"]
            replace_image(pbr["baseColorTexture"]["index"], maps[kind]["basecolor"])
            replace_image(m["normalTexture"]["index"], maps[kind]["normal"])
            replace_image(pbr["metallicRoughnessTexture"]["index"], maps[kind]["orm"])
            done.add(mi)
        if name == "skin" and "normalTexture" in m:   # už má mikroreliéf: jen nové mapy
            replace_image(m["normalTexture"]["index"], skin["normal"])
            replace_image(m["pbrMetallicRoughness"]["metallicRoughnessTexture"]["index"], skin["orm"])
        elif name == "skin":
            tn = add_image(j, b, skin["normal"], "image/jpeg", "skin_normal")
            to = add_image(j, b, skin["orm"], "image/jpeg", "skin_orm")
            m["normalTexture"] = {"index": tn}
            pbr = m.setdefault("pbrMetallicRoughness", {})
            pbr["metallicRoughnessTexture"] = {"index": to}
            pbr["metallicFactor"], pbr["roughnessFactor"] = 0.0, 1.0
    # barvy vrcholů: ocel neutrálně šedá (bez modrého nádechu), látky přirozená barviva (méně syté) – jen jednou
    first = j.setdefault("extras", {}).get("voxario_npc_pbr", 0) < 2
    j["extras"]["voxario_npc_pbr"] = 2
    for mesh in (j["meshes"] if first else []):
        for prim in mesh["primitives"]:
            name = mats[prim["material"]].get("name", "")
            if "COLOR_0" not in prim["attributes"] or name not in ("steel pbr", "cloth pbr", "leather pbr"):
                continue
            a = j["accessors"][prim["attributes"]["COLOR_0"]]
            c = read(j, b, prim["attributes"]["COLOR_0"]).astype(np.float32)
            if a["componentType"] != 5126:
                c = c / (255.0 if a["componentType"] == 5121 else 65535.0)
            rgb = c[:, :3]
            lum = rgb @ np.array([0.299, 0.587, 0.114], np.float32)
            if name == "steel pbr":
                L = np.where(lum > 0.45, 0.6 + (lum - 0.45) * 0.3, np.maximum(lum, 0.24) * 1.05)   # leštěná / černěná ocel
                rgb = np.stack([L * 1.0, L * 0.985, L * 0.965], -1) * 0.88 + rgb * 0.12
            elif name == "cloth pbr":
                rgb = (lum[:, None] + (rgb - lum[:, None]) * 0.72) * 0.94
            else:
                rgb = (lum[:, None] + (rgb - lum[:, None]) * 0.85)
            c[:, :3] = np.clip(rgb, 0, 1)
            prim["attributes"]["COLOR_0"] = write(j, b, c.astype(np.float32), 5126, "VEC4" if c.shape[1] == 4 else "VEC3")
    save_glb(path, j, compact(j, b))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cache", default=os.environ.get("ERYNDOR_TEXTURE_CACHE", str(pathlib.Path.home() / ".cache" / "eryndor-polyhaven")))
    ap.add_argument("--size", type=int, default=1024)
    a = ap.parse_args()
    maps = {k: build_maps(k, pathlib.Path(a.cache), a.size) for k in KINDS}
    (OUT / "CREDITS.txt").write_text("Materiály brnění a oděvů NPC: fotoskeny Poly Haven (https://polyhaven.com), CC0 1.0.\n"
                                     + "".join(f"{k}: https://polyhaven.com/a/{v[0]}\n" for k, v in KINDS.items()), encoding="utf-8")
    skin = skin_maps()
    for f in sorted(HUMANS.glob("*.glb")):
        n = process(f, maps)
        refine(f, maps, skin)
        print(f"{f.name}: {n} nových dílů, materiály a barvy obnoveny")


if __name__ == "__main__":
    main()
