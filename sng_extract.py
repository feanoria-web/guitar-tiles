#!/usr/bin/env python3
"""Clone Hero .sng ayiklayici — kullanim: python3 sng_extract.py dosya.sng [hedef_klasor]"""
import struct, sys, os

def read_sng(path, out_dir):
    with open(path, "rb") as f:
        data = f.read()
    assert data[:6] == b"SNGPKG", "Bu bir .sng dosyasi degil"
    pos = 6 + 4                       # magic + versiyon
    mask = data[pos:pos+16]; pos += 16

    # --- Metadata ---
    meta_len = struct.unpack_from("<Q", data, pos)[0]; pos += 8
    meta_end = pos + meta_len
    count = struct.unpack_from("<Q", data, pos)[0]; pos += 8
    meta = {}
    for _ in range(count):
        klen = struct.unpack_from("<i", data, pos)[0]; pos += 4
        key = data[pos:pos+klen].decode(); pos += klen
        vlen = struct.unpack_from("<i", data, pos)[0]; pos += 4
        meta[key] = data[pos:pos+vlen].decode(); pos += vlen
    pos = meta_end

    # --- Dosya indeksi ---
    pos += 8                          # indeks bolumu uzunlugu (atla)
    fcount = struct.unpack_from("<Q", data, pos)[0]; pos += 8
    files = []
    for _ in range(fcount):
        nlen = data[pos]; pos += 1
        name = data[pos:pos+nlen].decode(); pos += nlen
        flen = struct.unpack_from("<Q", data, pos)[0]; pos += 8
        foff = struct.unpack_from("<Q", data, pos)[0]; pos += 8
        files.append((name, flen, foff))

    # --- Ayikla (XOR maskesini coz) ---
    os.makedirs(out_dir, exist_ok=True)
    for name, flen, foff in files:
        raw = data[foff:foff+flen]
        clear = bytes(b ^ (mask[i % 16] ^ (i & 0xFF)) for i, b in enumerate(raw))
        with open(os.path.join(out_dir, name), "wb") as f:
            f.write(clear)
        print(f"  {name}  ({flen:,} bayt)")

    # song.ini uret ki klasor Clone Hero uyumlu olsun
    with open(os.path.join(out_dir, "song.ini"), "w") as f:
        f.write("[song]\n")
        for k, v in meta.items():
            f.write(f"{k} = {v}\n")
    print("  song.ini (metadata'dan uretildi)")
    return meta, files

if __name__ == "__main__":
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else os.path.splitext(src)[0]
    meta, files = read_sng(src, dst)
    print(f"\n{meta.get('artist','?')} - {meta.get('name','?')} | {len(files)} dosya ayiklandi -> {dst}")
