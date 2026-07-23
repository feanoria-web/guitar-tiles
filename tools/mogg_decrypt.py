#!/usr/bin/env python3
"""Decrypt encrypted Rock Band MOGG files (versions 0x0B-0x10).
Based on themethod3 (github.com/DarkRTA/themethod3).
Usage: python mogg_decrypt.py input.mogg output.ogg
"""
import sys
import struct
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

# Keys from themethod3/src/keys.rs
CTR_KEY_0B = bytes([0x37,0xb2,0xe2,0xb9,0x1c,0x74,0xfa,0x9e,0x38,0x81,0x08,0xea,0x36,0x23,0xdb,0xe4])

HV_KEYS = {
    0x0C: bytes([0x01,0x22,0x00,0x38,0xd2,0x01,0x78,0x8b,0xdd,0xcd,0xd0,0xf0,0xfe,0x3e,0x24,0x7f]),
    0x0D: bytes([0x01,0x22,0x00,0x38,0xd2,0x01,0x78,0x8b,0xdd,0xcd,0xd0,0xf0,0xfe,0x3e,0x24,0x7f]),  # same as 0C
    0x0E: bytes([0x51,0x73,0xad,0xe5,0xb3,0x99,0xb8,0x61,0x58,0x1a,0xf9,0xb8,0x1e,0xa7,0xbe,0xbf]),
    0x0F: bytes([0xc6,0x22,0x94,0x30,0xd8,0x3c,0x84,0x14,0x08,0x73,0x7c,0xf2,0x23,0xf6,0xeb,0x5a]),
    0x10: bytes([0x02,0x1a,0x83,0xf3,0x97,0xe9,0xd4,0xb8,0x06,0x74,0x14,0x6b,0x30,0x4c,0x00,0x91]),
}

HIDDEN_KEYS = [
    bytes([0x7f,0x95,0x5b,0x9d,0x94,0xba,0x12,0xf1,0xd7,0x5a,0x67,0xd9,0x16,0x45,0x28,0xdd,0x61,0x55,0x55,0xaf,0x23,0x91,0xd6,0x0a,0x3a,0x42,0x81,0x18,0xb4,0xf7,0xf3,0x04]),
    bytes([0x78,0x96,0x5d,0x92,0x92,0xb0,0x47,0xac,0x8f,0x5b,0x6d,0xdc,0x1c,0x41,0x7e,0xda,0x6a,0x55,0x53,0xaf,0x20,0xc8,0xdc,0x0a,0x66,0x43,0xdd,0x1c,0xb2,0xa5,0xa4,0x0c]),
    bytes([0x7e,0x92,0x5c,0x93,0x90,0xed,0x4a,0xad,0x8b,0x07,0x36,0xd3,0x10,0x41,0x78,0x8f,0x60,0x08,0x55,0xa8,0x26,0xcf,0xd0,0x0f,0x65,0x11,0x84,0x45,0xb1,0xa0,0xfa,0x57]),
    bytes([0x79,0x97,0x0b,0x90,0x92,0xb0,0x44,0xad,0x8a,0x0e,0x60,0xd9,0x14,0x11,0x7e,0x8d,0x35,0x5d,0x5c,0xfb,0x21,0x9c,0xd3,0x0e,0x32,0x40,0xd1,0x48,0xb8,0xa7,0xa1,0x0d]),
    bytes([0x28,0xc3,0x5d,0x97,0xc1,0xec,0x42,0xf1,0xdc,0x5d,0x37,0xda,0x14,0x47,0x79,0x8a,0x32,0x5c,0x54,0xf2,0x72,0x9d,0xd3,0x0d,0x67,0x4c,0xd6,0x49,0xb4,0xa2,0xf3,0x50]),
    bytes([0x28,0x96,0x5e,0x95,0xc5,0xe9,0x45,0xad,0x8a,0x5d,0x64,0x8e,0x17,0x40,0x2e,0x87,0x36,0x58,0x06,0xfd,0x75,0x90,0xd0,0x5f,0x3a,0x40,0xd4,0x4c,0xb0,0xf7,0xa7,0x04]),
    bytes([0x2c,0x96,0x01,0x96,0x9b,0xbc,0x15,0xa6,0xde,0x0e,0x65,0x8d,0x17,0x47,0x2f,0xdd,0x63,0x54,0x55,0xaf,0x76,0xca,0x84,0x5f,0x62,0x44,0x80,0x4a,0xb3,0xf4,0xf4,0x0c]),
    bytes([0x7e,0xc4,0x0e,0xc6,0x9a,0xeb,0x43,0xa0,0xdb,0x0a,0x64,0xdf,0x1c,0x42,0x24,0x89,0x63,0x5c,0x55,0xf3,0x71,0x90,0xdc,0x5d,0x60,0x40,0xd1,0x4d,0xb2,0xa3,0xa7,0x0d]),
    bytes([0x2c,0x9a,0x0b,0x90,0x9a,0xbe,0x47,0xa7,0x88,0x5a,0x6d,0xdf,0x13,0x1d,0x2e,0x8b,0x60,0x5e,0x55,0xf2,0x74,0x9c,0xd7,0x0e,0x60,0x40,0x80,0x1c,0xb7,0xa1,0xf4,0x02]),
    bytes([0x28,0x96,0x5b,0x95,0xc1,0xe9,0x40,0xa3,0x8f,0x0c,0x32,0xdf,0x43,0x1d,0x24,0x8d,0x61,0x09,0x54,0xab,0x27,0x9a,0xd3,0x58,0x60,0x16,0x84,0x4f,0xb3,0xa4,0xf3,0x0d]),
    bytes([0x25,0x93,0x08,0xc0,0x9a,0xbd,0x10,0xa2,0xd6,0x09,0x60,0x8f,0x11,0x1d,0x7a,0x8f,0x63,0x0b,0x5d,0xf2,0x21,0xec,0xd7,0x08,0x62,0x40,0x84,0x49,0xb0,0xad,0xf2,0x07]),
    bytes([0x29,0xc3,0x0c,0x96,0x96,0xeb,0x10,0xa0,0xda,0x59,0x32,0xd3,0x17,0x41,0x25,0xdc,0x63,0x08,0x04,0xae,0x77,0xcb,0x84,0x5a,0x60,0x4d,0xdd,0x45,0xb5,0xf4,0xa0,0x05]),
]

def lcg(x):
    return (x * 0x19660d + 0x3c6ef35f) & 0xFFFFFFFF

def get_masher():
    masher_word = 0xeb
    result = bytearray(32)
    for idx in range(8):
        if idx == 0:
            masher_word = 0xeb
        masher_word = (masher_word * 0x19660e + 0x3c6ef35f) & 0xFFFFFFFF
        struct.pack_into('<I', result, idx * 4, masher_word)
    return bytes(result)

def roll(x):
    return (x + 0x13) % 0x20

def shuffle1(key):
    for i in range(8):
        o = roll(i * 4)
        key[o], key[i*4+2] = key[i*4+2], key[o]
        o = roll(i*4+3)
        key[o], key[i*4+1] = key[i*4+1], key[o]

def shuffle2(key):
    for i in range(8):
        key[(7-i)*4+1], key[i*4+2] = key[i*4+2], key[(7-i)*4+1]
        key[(7-i)*4], key[i*4+3] = key[i*4+3], key[(7-i)*4]

def shuffle3(key):
    for i in range(8):
        o = roll((7-i)*4+1)
        key[o], key[i*4+2] = key[i*4+2], key[o]
        key[(7-i)*4], key[i*4+3] = key[i*4+3], key[(7-i)*4]

def shuffle4(key):
    for i in range(8):
        key[(7-i)*4+1], key[i*4+2] = key[i*4+2], key[(7-i)*4+1]
        o = roll((7-i)*4)
        key[o], key[i*4+3] = key[i*4+3], key[o]

def shuffle5(key):
    for i in range(8):
        o = roll(i*4+2)
        key[(7-i)*4+1], key[o] = key[o], key[(7-i)*4+1]
        key[(7-i)*4], key[i*4+3] = key[i*4+3], key[(7-i)*4]

def shuffle6(key):
    for i in range(8):
        key[(7-i)*4+1], key[i*4+2] = key[i*4+2], key[(7-i)*4+1]
        o = roll(i*4+3)
        key[(7-i)*4], key[o] = key[o], key[(7-i)*4]

def supershuffle(key):
    shuffle1(key); shuffle2(key); shuffle3(key)
    shuffle4(key); shuffle5(key); shuffle6(key)

def rotr8(x, n):
    x &= 0xFF; n &= 7
    return ((x >> n) | (x << (8 - n))) & 0xFF

def rotl8(x, n):
    x &= 0xFF; n &= 7
    return ((x << n) | (x >> (8 - n))) & 0xFF

def o_func(a1, a2, op):
    a1 &= 0xFF; a2 &= 0xFF
    not_a1 = 1 if a1 == 0 else 0
    not_a2 = 1 if a2 == 0 else 0
    ops = {
        0: lambda: a2 + rotr8(a1, not_a2),
        1: lambda: a2 + rotr8(a1, 3),
        2: lambda: a2 + rotl8(a1, 1),
        3: lambda: a2 ^ (((a1 >> (a2&7)) | (a1 << ((-a2)&7))) & 0xFF),
        4: lambda: a2 ^ rotl8(a1, 4),
        5: lambda: a2 + ((a2 ^ rotr8(a1, 3)) & 0xFF),
        6: lambda: a2 + rotl8(a1, 2),
        7: lambda: a2 + not_a1,
        8: lambda: a2 ^ rotr8(a1, not_a2),
        9: lambda: a2 ^ ((a2 + rotl8(a1, 3)) & 0xFF),
        10: lambda: a2 + rotl8(a1, 3),
        11: lambda: a2 + rotl8(a1, 4),
        12: lambda: a1 ^ a2,
        13: lambda: a2 ^ not_a1,
        14: lambda: a2 ^ ((a2 + rotr8(a1, 3)) & 0xFF),
        15: lambda: a2 ^ rotl8(a1, 3),
        16: lambda: a2 ^ rotl8(a1, 2),
        17: lambda: a2 + ((a2 ^ rotl8(a1, 3)) & 0xFF),
        18: lambda: a2 + ((a1 ^ a2) & 0xFF),
        19: lambda: a1 + a2,
        20: lambda: a2 ^ rotr8(a1, 3),
        21: lambda: a2 ^ ((a1 + a2) & 0xFF),
        22: lambda: rotr8(a1, not_a2),
        23: lambda: a2 + rotr8(a1, 1),
        24: lambda: ((a1 >> (a2&7)) | (a1 << ((-a2)&7))) & 0xFF,
        25: lambda: 128 if (a1==0 and a2==0) else (1 if a1==0 else 0),
        26: lambda: a2 + rotr8(a1, 2),
        27: lambda: a2 ^ rotr8(a1, 1),
        28: lambda: o_func((~a1)&0xFF, a2, 24),
        29: lambda: a2 ^ rotr8(a1, 2),
        30: lambda: a2 + (((a1>>(a2&7))|(a1<<((-a2)&7)))&0xFF),
        31: lambda: a2 ^ rotl8(a1, 1),
        32: lambda: (((a1<<8)|170|(a1^255))>>4) ^ a2,
        33: lambda: (((a1^255)|(a1<<8))>>3) ^ a2,
        34: lambda: (((a1<<8)^65280|a1)>>2) ^ a2,
        35: lambda: (((a1^92)|(a1<<8))>>5) ^ a2,
        36: lambda: (((a1<<8)|101|(a1^60))>>2) ^ a2,
        37: lambda: (((a1^54)|(a1<<8))>>2) ^ a2,
        38: lambda: (((a1^54)|(a1<<8))>>4) ^ a2,
        39: lambda: (((a1^92)|(a1<<8)|54)>>1) ^ a2,
        40: lambda: (((a1^255)|(a1<<8))>>5) ^ a2,
        41: lambda: ((((~a1)&0xFF)<<8|a1)>>6) ^ a2,
        42: lambda: (((a1^92)|(a1<<8))>>3) ^ a2,
        43: lambda: (((a1^60)|101|(a1<<8))>>5) ^ a2,
        44: lambda: (((a1^54)|(a1<<8))>>1) ^ a2,
        45: lambda: (((a1^101)|(a1<<8)|60)>>6) ^ a2,
        46: lambda: (((a1^92)|(a1<<8))>>2) ^ a2,
        47: lambda: (((a2^170)|(a2<<8)|255)>>3) ^ a1,
        48: lambda: (((a1^99)|(a1<<8)|92)>>6) ^ a2,
        49: lambda: (((a1^92)|(a1<<8)|54)>>7) ^ a2,
        50: lambda: (((a1^92)|(a1<<8))>>6) ^ a2,
        51: lambda: (((a1<<8)^65280|a1)>>3) ^ a2,
        52: lambda: (((a1^255)|(a1<<8))>>6) ^ a2,
        53: lambda: (((a1<<8)^65280|a1)>>5) ^ a2,
        54: lambda: (((a1^60)|101|(a1<<8))>>4) ^ a2,
        55: lambda: (((a1^99)|(a1<<8)|92)>>3) ^ a2,
        56: lambda: (((a1^99)|(a1<<8)|92)>>5) ^ a2,
        57: lambda: (((a1^175)|(a1<<8)|250)>>5) ^ a2,
        58: lambda: (((a1^92)|(a1<<8)|54)>>5) ^ a2,
        59: lambda: (((a1^92)|(a1<<8)|54)>>3) ^ a2,
        60: lambda: (((a1^54)|(a1<<8))>>3) ^ a2,
        61: lambda: (((a1^99)|(a1<<8)|92)>>4) ^ a2,
        62: lambda: (((a1^255)|(a1<<8)|175)>>6) ^ a2,
        63: lambda: (((a1^255)|(a1<<8))>>2) ^ a2,
    }
    return ops.get(op, lambda: 0)() & 0xFF

def ascii_digit_to_hex(h):
    if 0x61 <= h <= 0x66: return h - 87
    elif 0x41 <= h <= 0x46: return h - 0x37
    else: return (h - 0x30) & 0xFF

def hex_string_to_bytes(s):
    return bytes(ascii_digit_to_hex(s[i*2])*16 + ascii_digit_to_hex(s[i*2+1]) & 0xFF for i in range(16))

def grind_array(magic_a_in, magic_b_in, key_in, version):
    key = bytearray(key_in)
    magic_a = magic_a_in & 0xFFFFFFFF
    magic_b = magic_b_in & 0xFFFFFFFF

    array2 = [0]*256
    ma = magic_a
    for i in range(256):
        array2[i] = (ma & 0xFF) >> 3
        ma = lcg(ma)

    if magic_b == 0:
        magic_b = 0x303f

    array_used = [0]*64
    array1 = [0]*64
    mb = magic_b
    for i in range(0x20):
        while True:
            mb = lcg(mb)
            num = (mb >> 2) & 0x1f
            if array_used[num] == 0:
                break
        array1[i] = num
        array_used[num] = 1

    array3 = list(array2)

    if version > 13:
        array4 = [0]*256
        ma2 = magic_b_in & 0xFFFFFFFF
        for i in range(256):
            array4[i] = ((ma2 & 0xFF) >> 2) & 0x3f
            ma2 = lcg(ma2)

        num1 = magic_a_in & 0xFFFFFFFF
        for i in range(32, 64):
            while True:
                num1 = lcg(num1)
                num = ((num1 >> 2) & 0x1f) + 0x20
                if array_used[num] == 0:
                    break
            array1[i] = num
            array_used[num] = 1
        array3 = array4

    for j in range(16):
        num3 = key[j]
        for k in range(0, 16, 2):
            lookup_idx = key[k]
            op_idx = array3[lookup_idx] if lookup_idx < 256 else 0
            op = array1[op_idx] if op_idx < 64 else 0
            num3 = o_func(num3, key[k+1], op)
        key[j] = num3 & 0xFF

    return bytes(key)

def gen_key(hv_key, data, version):
    hmx_header_size = struct.unpack_from('<I', data, 16)[0]
    base_offset = 20 + hmx_header_size * 8 + 16

    # Xbox 360 path: decrypt key_mask
    key_mask_enc = data[base_offset+32:base_offset+48]
    cipher = Cipher(algorithms.AES(hv_key), modes.ECB())
    dec = cipher.decryptor()
    key_mask = dec.update(key_mask_enc) + dec.finalize()

    magic_a = struct.unpack_from('<I', data, base_offset)[0]
    magic_b = struct.unpack_from('<I', data, base_offset+8)[0]

    key_index_offset = base_offset + 48
    key_index_raw = struct.unpack_from('<Q', data, key_index_offset)[0]
    key_index = (key_index_raw % 6) + 6  # Xbox path

    selected_key = bytearray(HIDDEN_KEYS[key_index])

    # Reveal key
    masher = get_masher()
    for _ in range(14):
        supershuffle(selected_key)
    revealed = bytes(a ^ b for a, b in zip(selected_key, masher))

    hex_key = hex_string_to_bytes(revealed)
    ground = grind_array(magic_a, magic_b, hex_key, version)

    final_key = bytes(a ^ b for a, b in zip(ground, key_mask))
    return final_key

def hmxa_to_ogg(data, mogg_data, num_entries):
    result = bytearray(data)
    base_offset = 20 + num_entries * 8 + 16
    magic_a = struct.unpack_from('<I', mogg_data, base_offset)[0]
    magic_b = struct.unpack_from('<I', mogg_data, base_offset+8)[0]

    magic_hash_a = lcg(lcg(magic_a ^ 0x5c5c5c5c))
    magic_hash_b = lcg(magic_b ^ 0x36363636)

    result[0:4] = b'OggS'
    val_a = struct.unpack_from('>I', result, 12)[0] ^ magic_hash_a
    struct.pack_into('>I', result, 12, val_a & 0xFFFFFFFF)
    val_b = struct.unpack_from('>I', result, 20)[0] ^ magic_hash_b
    struct.pack_into('>I', result, 20, val_b & 0xFFFFFFFF)
    return bytes(result)

def decrypt_mogg(data):
    version = data[0]
    if version == 0x0A:
        ogg_offset = struct.unpack_from('<I', data, 4)[0]
        return data[ogg_offset:]

    if version < 0x0B or version > 0x10:
        raise ValueError(f"Unsupported MOGG version 0x{version:02X}")

    ogg_offset = struct.unpack_from('<I', data, 4)[0]

    # Get decryption key
    if version == 0x0B:
        ctr_key = CTR_KEY_0B
    else:
        hv_key = HV_KEYS.get(version)
        if not hv_key:
            raise ValueError(f"No HV key for version 0x{version:02X}")
        ctr_key = gen_key(hv_key, data, version)

    # Read nonce
    hmx_header_size = struct.unpack_from('<I', data, 16)[0]
    nonce_offset = 20 + hmx_header_size * 8
    nonce = data[nonce_offset:nonce_offset+16]

    # Decrypt with AES-128 CTR (nonce as initial counter, little-endian)
    nonce_int = int.from_bytes(nonce, 'little')
    encrypted = data[ogg_offset:]

    # Use AES-CTR: encrypt counter blocks and XOR
    result = bytearray(len(encrypted))
    cipher_ecb = Cipher(algorithms.AES(ctr_key), modes.ECB()).encryptor()

    # Process in 64KB chunks for efficiency
    for chunk_start in range(0, len(encrypted), 65536):
        chunk_end = min(chunk_start + 65536, len(encrypted))
        chunk_blocks = (chunk_end - chunk_start + 15) // 16

        # Build all counter blocks for this chunk
        counter_data = b''
        for i in range(chunk_blocks):
            ctr_val = (nonce_int + (chunk_start // 16) + i) & ((1 << 128) - 1)
            counter_data += ctr_val.to_bytes(16, 'little')

        keystream = cipher_ecb.update(counter_data)

        for i in range(chunk_end - chunk_start):
            result[chunk_start + i] = encrypted[chunk_start + i] ^ keystream[i]

    decrypted = bytes(result)

    # Check for HMXA magic
    if decrypted[:4] == b'HMXA':
        decrypted = hmxa_to_ogg(decrypted, data, hmx_header_size)

    if decrypted[:4] != b'OggS':
        raise ValueError(f"Decryption failed — expected OggS, got {decrypted[:4].hex()}")

    return decrypted

def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} input.mogg output.ogg", file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]

    with open(input_path, 'rb') as f:
        data = f.read()

    try:
        ogg = decrypt_mogg(data)
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    with open(output_path, 'wb') as f:
        f.write(ogg)

    print(f"OK: {len(ogg)} bytes written to {output_path}")

if __name__ == '__main__':
    main()
