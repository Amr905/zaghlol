"""Minimal, deterministic writer for the Rive runtime file format (v7).

Type/property keys come from rive_defs.json (extracted from rive-app/rive-runtime,
see extract_defs.py). Objects are written in the order they are added; ids are
artboard-local component indices (artboard = 0), exactly as the runtime importer
numbers them (Component and KeyFrameInterpolator claim a slot).
"""
import json
import struct
from pathlib import Path

_DEFS = json.loads((Path(__file__).with_name("rive_defs.json")).read_text())["classes"]
_SLOT_TYPES = None  # filled lazily


def _is_a(cls, ancestor):
    while cls in _DEFS:
        if cls == ancestor:
            return True
        cls = _DEFS[cls]["super"]
    return False


def _prop(cls, name):
    c = cls
    while c in _DEFS:
        if name in _DEFS[c]["props"]:
            key, kind = _DEFS[c]["props"][name]
            return key, kind
        c = _DEFS[c]["super"]
    raise KeyError(f"{cls}.{name}")


def varuint(n):
    assert n >= 0
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def _value(kind, v):
    if kind == "uint":
        return varuint(int(v))
    if kind == "float":
        return struct.pack("<f", float(v))
    if kind == "color":
        return struct.pack("<I", int(v))
    if kind == "bool":
        return b"\x01" if v else b"\x00"
    if kind == "string":
        raw = v.encode("utf-8")
        return varuint(len(raw)) + raw
    raise ValueError(kind)


# ToC field index per kind (2 bits): 0 uint/bool, 1 string, 2 float, 3 color
_TOC = {"uint": 0, "bool": 0, "string": 1, "float": 2, "color": 3}


class RiveFile:
    def __init__(self):
        self._objs = []  # (cls, {key: (kind, value)})
        self._toc = {}
        self.slot = 0  # next artboard-local component index (artboard itself = 0)
        self._artboard_open = False
        self.anim_count = 0

    def add(self, cls, **props):
        """Append an object. Returns its artboard-local slot index if it claims one."""
        enc = {}
        for name, v in props.items():
            key, kind = _prop(cls, name)
            enc[key] = (kind, v)
            self._toc[key] = _TOC[kind]
        self._objs.append((cls, enc))
        if cls == "Artboard":
            self._artboard_open = True
            self.slot = 1
            return 0
        if self._artboard_open and (_is_a(cls, "Component") or _is_a(cls, "KeyFrameInterpolator")):
            i = self.slot
            self.slot += 1
            return i
        return None

    def to_bytes(self):
        out = bytearray(b"RIVE")
        out += varuint(7) + varuint(0) + varuint(0)
        keys = sorted(self._toc)
        for k in keys:
            out += varuint(k)
        out += varuint(0)
        for i in range(0, len(keys), 4):
            word = 0
            for j, k in enumerate(keys[i:i + 4]):
                word |= self._toc[k] << (2 * j)
            out += struct.pack("<I", word)
        for cls, enc in self._objs:
            out += varuint(_DEFS[cls]["typeKey"])
            for key in sorted(enc):
                kind, v = enc[key]
                out += varuint(key) + _value(kind, v)
            out += varuint(0)
        return bytes(out)
