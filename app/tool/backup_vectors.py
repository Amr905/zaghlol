#!/usr/bin/env python3
"""T-148: independent generator of the ZGLB v1 backup format vectors.

Writes app/test/fixtures/backup/zglb-v1-vectors.json. It shares no code with
the Dart implementation: Python's `unicodedata` does NFC, `argon2-cffi` (the
reference C implementation) does Argon2id, and `cryptography` (OpenSSL) does
HKDF-SHA256 and AES-256-GCM. CI checks only the Dart side against the
committed output; rerun this after a deliberate format change:

    pip install cryptography==50.0.1 argon2-cffi==25.1.0
    python3 app/tool/backup_vectors.py

Every input is synthetic (design note §9). Nothing here is a real secret.
"""

import hashlib
import json
import os
import sys
import unicodedata

from argon2.low_level import Type, hash_secret_raw
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

OUT = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "test", "fixtures", "backup", "zglb-v1-vectors.json",
)

ZS = {c for c in range(0x110000)
      if unicodedata.category(chr(c)) == "Zs"}


def normalize(passphrase: str) -> str:
    out = []
    for ch in passphrase:
        c = ord(ch)
        if 0x0660 <= c <= 0x0669:
            out.append(chr(0x30 + c - 0x0660))
        elif 0x06F0 <= c <= 0x06F9:
            out.append(chr(0x30 + c - 0x06F0))
        elif c in ZS:
            out.append(" ")
        else:
            out.append(ch)
    return unicodedata.normalize("NFC", "".join(out))


def cbor_head(major: int, value: int) -> bytes:
    m = major << 5
    if value < 24:
        return bytes([m | value])
    if value < 0x100:
        return bytes([m | 24, value])
    if value < 0x10000:
        return bytes([m | 25]) + value.to_bytes(2, "big")
    if value < 0x100000000:
        return bytes([m | 26]) + value.to_bytes(4, "big")
    return bytes([m | 27]) + value.to_bytes(8, "big")


def cu(v: int) -> bytes:
    return cbor_head(0, v)


def cb(b: bytes) -> bytes:
    return cbor_head(2, len(b)) + b


def ct(s: str) -> bytes:
    e = s.encode("utf-8")
    return cbor_head(3, len(e)) + e


def cmap(entries) -> bytes:
    out = cbor_head(5, len(entries))
    for k, v in entries:
        out += cu(k) + v
    return out


def hkdf(ikm: bytes, salt, info: bytes, length: int) -> bytes:
    return HKDF(algorithm=hashes.SHA256(), length=length, salt=salt,
                info=info).derive(ikm)


def seq_bytes(seed: int, n: int) -> bytes:
    """Deterministic synthetic bytes: SHA-256 in counter mode over a seed."""
    out = bytearray()
    counter = 0
    while len(out) < n:
        out += hashlib.sha256(
            b"ZGLB test " + bytes([seed]) + counter.to_bytes(4, "big")
        ).digest()
        counter += 1
    return bytes(out[:n])


def payload(n: int) -> bytes:
    return bytes(((i * 131) + (i >> 8)) & 0xFF for i in range(n))


def cps(s: str):
    return " ".join("%04X" % ord(ch) for ch in s)


def make_case(name, passphrase, alt, chunk_size, payload_len, seed):
    p_str = normalize(passphrase)
    for a in alt:
        assert normalize(a) == p_str, a
    p = p_str.encode("utf-8")
    salt = seq_bytes(seed, 16)
    kbk = seq_bytes(seed + 1, 32)
    wrap_nonce = seq_bytes(seed + 2, 12)
    file_id = seq_bytes(seed + 3, 16)
    nonce_prefix = seq_bytes(seed + 4, 8)
    m, t, par = 65536, 3, 1
    created_at = 1762848000000 + seed
    seq_no, schema, contents = 7, 3, 1
    platform, app_version = "android", "0.1.0+1"

    kek = hash_secret_raw(p, salt, time_cost=t, memory_cost=m,
                          parallelism=par, hash_len=32, type=Type.ID,
                          version=0x13)
    kbk_id = hkdf(kbk, None, b"ZGLB v1 key-id", 16)
    kdf_cbor = cmap([(1, cu(1)), (2, cb(salt)), (3, cu(m)), (4, cu(t)),
                     (5, cu(par))])
    wrap_aad = b"ZGLB v1 wrap" + kdf_cbor + kbk_id
    wrap_ct = AESGCM(kek).encrypt(wrap_nonce, kbk, wrap_aad)
    header = cmap([
        (1, kdf_cbor),
        (2, cmap([(1, cu(1)), (2, cb(wrap_nonce)), (3, cb(wrap_ct))])),
        (3, cb(kbk_id)),
        (4, cb(file_id)),
        (5, cb(nonce_prefix)),
        (6, cu(chunk_size)),
        (7, cu(created_at)),
        (8, cu(seq_no)),
        (9, cu(schema)),
        (10, cu(contents)),
        (11, ct(platform)),
        (12, ct(app_version)),
    ])
    header_block = b"ZGLB" + bytes([1]) + len(header).to_bytes(2, "big") + header
    k_chunk = hkdf(kbk, file_id, b"ZGLB v1 chunk", 32)
    k_snap = hkdf(kbk, file_id, b"ZGLB v1 db-snapshot", 32)

    data = payload(payload_len)
    pieces = [data[i:i + chunk_size] for i in range(0, len(data), chunk_size)]
    if not pieces:
        pieces = [b""]
    gcm = AESGCM(k_chunk)
    chunks = []
    for i, piece in enumerate(pieces):
        is_last = i == len(pieces) - 1
        nonce = nonce_prefix + i.to_bytes(4, "big")
        aad = header_block + i.to_bytes(4, "big") + bytes([1 if is_last else 0])
        chunks.append(gcm.encrypt(nonce, piece, aad))
    file_bytes = header_block + b"".join(chunks)

    return {
        "name": name,
        "passphrase": passphrase,
        "passphraseCodePoints": cps(passphrase),
        "equivalentPassphrases": alt,
        "normalizedCodePoints": cps(p_str),
        "pHex": p.hex(),
        "saltHex": salt.hex(),
        "memoryKiB": m,
        "iterations": t,
        "parallelism": par,
        "kekHex": kek.hex(),
        "kbkHex": kbk.hex(),
        "wrapNonceHex": wrap_nonce.hex(),
        "wrapCtHex": wrap_ct.hex(),
        "kbkIdHex": kbk_id.hex(),
        "fileIdHex": file_id.hex(),
        "noncePrefixHex": nonce_prefix.hex(),
        "createdAtMs": created_at,
        "seq": seq_no,
        "schemaVersion": schema,
        "contentsVersion": contents,
        "platform": platform,
        "appVersion": app_version,
        "chunkSize": chunk_size,
        "payloadLength": payload_len,
        "payloadFormula": "byte[i] = (i * 131 + (i >> 8)) & 0xff",
        "kChunkHex": k_chunk.hex(),
        "kSnapHex": k_snap.hex(),
        "headerBlockHex": header_block.hex(),
        "chunkCount": len(chunks),
        "firstChunkSha256": hashlib.sha256(chunks[0]).hexdigest(),
        "firstChunkTagHex": chunks[0][-16:].hex(),
        "lastChunkSha256": hashlib.sha256(chunks[-1]).hexdigest(),
        "lastChunkTagHex": chunks[-1][-16:].hex(),
        "lastChunkLength": len(chunks[-1]),
        "fileLength": len(file_bytes),
        "fileSha256": hashlib.sha256(file_bytes).hexdigest(),
    }


# NFC pairs shared with the Kotlin and Swift unit tests (code points, hex).
# The Arabic compositions are every canonical composition with U+0653..0655;
# the Latin and Hangul rows prove the platform normalizer is a full NFC.
NFC_PAIRS = [
    ("0627 0653", "0622"),  # alef + madda above → آ
    ("0627 0654", "0623"),  # alef + hamza above → أ
    ("0648 0654", "0624"),  # waw + hamza above → ؤ
    ("0627 0655", "0625"),  # alef + hamza below → إ
    ("064A 0654", "0626"),  # yeh + hamza above → ئ
    ("06D5 0654", "06C0"),
    ("06C1 0654", "06C2"),
    ("06D2 0654", "06D3"),
    ("0623", "0623"),  # already composed
    ("0647 0645 0632 0629", "0647 0645 0632 0629"),  # همزة, unchanged
    ("0628 0651 0650", "0628 0650 0651"),  # shadda+kasra → kasra(ccc 32) first
    ("0065 0301", "00E9"),
    ("1100 1161 11A8", "AC01"),  # Hangul L V T → 각
    ("212B", "00C5"),  # angstrom sign → Å (singleton)
]


def nfc_rows():
    rows = []
    for src, want in NFC_PAIRS:
        s = "".join(chr(int(h, 16)) for h in src.split())
        got = cps(unicodedata.normalize("NFC", s))
        assert got == want, (src, got, want)
        rows.append({"input": src, "nfc": want})
    return rows


def main():
    # Arabic passphrase: Arabic-Indic ٣٤, Extended ۵, a no-break space and
    # a decomposed hamza (alef + U+0654) that NFC composes to أ.
    typed = "كلمة سر ٣٤۵ أمان"
    alt = [
        "كلمة سر 345 أمان",
        "كلمة سر ٣٤٥ أمان",
    ]
    cases = [
        make_case("arabic-2.5-chunks-64k", typed, alt, 65536, 65536 * 2 + 32768, 1),
        make_case("ascii-1.5-chunks-1m", "correct horse battery", [],
                  1 << 20, (1 << 20) + (1 << 19), 41),
        make_case("empty-payload", "empty payload pass", [], 65536, 0, 81),
        make_case("exact-2-chunks", "exact boundary pass", [], 65536, 65536 * 2, 121),
    ]
    doc = {
        "comment": "T-148 ZGLB v1 vectors. Synthetic. Produced by "
                   "app/tool/backup_vectors.py (Python cryptography + "
                   "argon2-cffi + unicodedata), independent of the Dart code.",
        "unicodeVersion": unicodedata.unidata_version,
        "nfc": nfc_rows(),
        "cases": cases,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=2, ensure_ascii=True)
        f.write("\n")
    print("wrote", os.path.relpath(OUT), file=sys.stderr)


if __name__ == "__main__":
    main()
