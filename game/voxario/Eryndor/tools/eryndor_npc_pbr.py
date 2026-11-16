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

# materiál dílu -> (fotosken, dlaždice v m, kovovost, násobek drsnosti, síla detailu barvy)
KINDS = {
    "steel": ("metal_plate_02", 0.55, 1.0, 0.62, 0.35),     # kované pláty: jemné škrábance, mapy drsnosti
    "gold": ("metal_plate_02", 0.4, 1.0, 0.45, 0.3),        # zlacené lemy a ozdoby (barvu dává návrh)
    "leather": ("brown_leather", 0.32, 0.0, 1.0, 0.55),     # kůže: póry, švy, ohyby
    "cloth": ("rough_linen", 0.22, 0.0, 1.0, 0.5),          # tkanina: vazba plátna
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
    asset, _, metal, rough_mul, detail = KINDS[kind]
    p = fetch(asset, cache, MAPS)
    OUT.mkdir(parents=True, exist_ok=True)
    alb = np.asarray(Image.open(p["albedo"]).convert("RGB").resize((size, size), Image.LANCZOS), np.float32) / 255
    lum = alb @ np.array([0.299, 0.587, 0.114])
    # detail: odbarvený jas kolem 1 (barva z návrhu), síla podle druhu
    det = lum / max(np.median(lum), 1e-3)
    det = 1.0 + (det - 1.0) * detail
    base = np.clip(det * 0.82, 0, 1)
    base_img = Image.fromarray((np.repeat(base[..., None], 3, 2) * 255 + 0.5).astype(np.uint8), "RGB")
    nrm_img = Image.open(p["normal"]).convert("RGB").resize((size, size), Image.LANCZOS)
    arm = np.asarray(Image.open(p["arm"]).convert("RGB").resize((size, size), Image.LANCZOS), np.float32) / 255
    orm = np.zeros_like(arm)
    orm[..., 0] = 0.55 + 0.45 * arm[..., 0]                         # okluze (jemně)
    orm[..., 1] = np.clip(arm[..., 1] * rough_mul, 0.08, 1.0)       # drsnost
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


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cache", default=os.environ.get("ERYNDOR_TEXTURE_CACHE", str(pathlib.Path.home() / ".cache" / "eryndor-polyhaven")))
    ap.add_argument("--size", type=int, default=1024)
    a = ap.parse_args()
    maps = {k: build_maps(k, pathlib.Path(a.cache), a.size) for k in KINDS}
    (OUT / "CREDITS.txt").write_text("Materiály brnění a oděvů NPC: fotoskeny Poly Haven (https://polyhaven.com), CC0 1.0.\n"
                                     + "".join(f"{k}: https://polyhaven.com/a/{v[0]}\n" for k, v in KINDS.items()), encoding="utf-8")
    for f in sorted(HUMANS.glob("*.glb")):
        print(f"{f.name}: {process(f, maps)} dílů")


if __name__ == "__main__":
    main()
