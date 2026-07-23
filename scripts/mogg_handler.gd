class_name MoggHandler
extends RefCounted

## Handles Rock Band .mogg files.
## MOGG = header + OGG Vorbis audio data (multi-channel).
## Supports unencrypted (0x0A) and encrypted (0x0B-0x11) versions.
## Decryption based on themethod3 (github.com/DarkRTA/themethod3) — AES-128 CTR.

var is_encrypted: bool = false
var ogg_offset: int = 0
var channel_count: int = 0

# --- Keys (from themethod3/src/keys.rs) ---
const CTR_KEY_0B: PackedByteArray = [
	0x37, 0xb2, 0xe2, 0xb9, 0x1c, 0x74, 0xfa, 0x9e,
	0x38, 0x81, 0x08, 0xea, 0x36, 0x23, 0xdb, 0xe4]

const HV_KEY_0C: PackedByteArray = [
	0x01, 0x22, 0x00, 0x38, 0xd2, 0x01, 0x78, 0x8b,
	0xdd, 0xcd, 0xd0, 0xf0, 0xfe, 0x3e, 0x24, 0x7f]

const HV_KEY_0E: PackedByteArray = [
	0x51, 0x73, 0xad, 0xe5, 0xb3, 0x99, 0xb8, 0x61,
	0x58, 0x1a, 0xf9, 0xb8, 0x1e, 0xa7, 0xbe, 0xbf]

const HV_KEY_0F: PackedByteArray = [
	0xc6, 0x22, 0x94, 0x30, 0xd8, 0x3c, 0x84, 0x14,
	0x08, 0x73, 0x7c, 0xf2, 0x23, 0xf6, 0xeb, 0x5a]

const HV_KEY_10: PackedByteArray = [
	0x02, 0x1a, 0x83, 0xf3, 0x97, 0xe9, 0xd4, 0xb8,
	0x06, 0x74, 0x14, 0x6b, 0x30, 0x4c, 0x00, 0x91]

const HV_KEY_11: PackedByteArray = [
	0x42, 0x66, 0x37, 0xb3, 0x68, 0x05, 0x9f, 0x85,
	0x6e, 0x96, 0xbd, 0x1e, 0xf9, 0x0e, 0x7f, 0xbd]

const HIDDEN_KEYS: Array = [
	[0x7f,0x95,0x5b,0x9d,0x94,0xba,0x12,0xf1,0xd7,0x5a,0x67,0xd9,0x16,0x45,0x28,0xdd,0x61,0x55,0x55,0xaf,0x23,0x91,0xd6,0x0a,0x3a,0x42,0x81,0x18,0xb4,0xf7,0xf3,0x04],
	[0x78,0x96,0x5d,0x92,0x92,0xb0,0x47,0xac,0x8f,0x5b,0x6d,0xdc,0x1c,0x41,0x7e,0xda,0x6a,0x55,0x53,0xaf,0x20,0xc8,0xdc,0x0a,0x66,0x43,0xdd,0x1c,0xb2,0xa5,0xa4,0x0c],
	[0x7e,0x92,0x5c,0x93,0x90,0xed,0x4a,0xad,0x8b,0x07,0x36,0xd3,0x10,0x41,0x78,0x8f,0x60,0x08,0x55,0xa8,0x26,0xcf,0xd0,0x0f,0x65,0x11,0x84,0x45,0xb1,0xa0,0xfa,0x57],
	[0x79,0x97,0x0b,0x90,0x92,0xb0,0x44,0xad,0x8a,0x0e,0x60,0xd9,0x14,0x11,0x7e,0x8d,0x35,0x5d,0x5c,0xfb,0x21,0x9c,0xd3,0x0e,0x32,0x40,0xd1,0x48,0xb8,0xa7,0xa1,0x0d],
	[0x28,0xc3,0x5d,0x97,0xc1,0xec,0x42,0xf1,0xdc,0x5d,0x37,0xda,0x14,0x47,0x79,0x8a,0x32,0x5c,0x54,0xf2,0x72,0x9d,0xd3,0x0d,0x67,0x4c,0xd6,0x49,0xb4,0xa2,0xf3,0x50],
	[0x28,0x96,0x5e,0x95,0xc5,0xe9,0x45,0xad,0x8a,0x5d,0x64,0x8e,0x17,0x40,0x2e,0x87,0x36,0x58,0x06,0xfd,0x75,0x90,0xd0,0x5f,0x3a,0x40,0xd4,0x4c,0xb0,0xf7,0xa7,0x04],
	[0x2c,0x96,0x01,0x96,0x9b,0xbc,0x15,0xa6,0xde,0x0e,0x65,0x8d,0x17,0x47,0x2f,0xdd,0x63,0x54,0x55,0xaf,0x76,0xca,0x84,0x5f,0x62,0x44,0x80,0x4a,0xb3,0xf4,0xf4,0x0c],
	[0x7e,0xc4,0x0e,0xc6,0x9a,0xeb,0x43,0xa0,0xdb,0x0a,0x64,0xdf,0x1c,0x42,0x24,0x89,0x63,0x5c,0x55,0xf3,0x71,0x90,0xdc,0x5d,0x60,0x40,0xd1,0x4d,0xb2,0xa3,0xa7,0x0d],
	[0x2c,0x9a,0x0b,0x90,0x9a,0xbe,0x47,0xa7,0x88,0x5a,0x6d,0xdf,0x13,0x1d,0x2e,0x8b,0x60,0x5e,0x55,0xf2,0x74,0x9c,0xd7,0x0e,0x60,0x40,0x80,0x1c,0xb7,0xa1,0xf4,0x02],
	[0x28,0x96,0x5b,0x95,0xc1,0xe9,0x40,0xa3,0x8f,0x0c,0x32,0xdf,0x43,0x1d,0x24,0x8d,0x61,0x09,0x54,0xab,0x27,0x9a,0xd3,0x58,0x60,0x16,0x84,0x4f,0xb3,0xa4,0xf3,0x0d],
	[0x25,0x93,0x08,0xc0,0x9a,0xbd,0x10,0xa2,0xd6,0x09,0x60,0x8f,0x11,0x1d,0x7a,0x8f,0x63,0x0b,0x5d,0xf2,0x21,0xec,0xd7,0x08,0x62,0x40,0x84,0x49,0xb0,0xad,0xf2,0x07],
	[0x29,0xc3,0x0c,0x96,0x96,0xeb,0x10,0xa0,0xda,0x59,0x32,0xd3,0x17,0x41,0x25,0xdc,0x63,0x08,0x04,0xae,0x77,0xcb,0x84,0x5a,0x60,0x4d,0xdd,0x45,0xb5,0xf4,0xa0,0x05],
]

func extract_ogg(mogg_data: PackedByteArray) -> PackedByteArray:
	if mogg_data.size() < 8:
		push_error("MoggHandler: data too small")
		return PackedByteArray()

	var version := mogg_data.decode_u32(0)
	if version == 0x0A:
		# Unencrypted
		ogg_offset = mogg_data.decode_u32(4)
		if ogg_offset >= mogg_data.size():
			push_error("MoggHandler: OGG offset (%d) beyond file size (%d)" % [ogg_offset, mogg_data.size()])
			return PackedByteArray()
		print("MoggHandler: version=0x%X (unencrypted), ogg_offset=%d, ogg_size=%d" % [version, ogg_offset, mogg_data.size() - ogg_offset])
		return mogg_data.slice(ogg_offset)

	# Encrypted versions 0x0B - 0x11
	if version < 0x0B or version > 0x11:
		is_encrypted = true
		push_error("MoggHandler: unsupported MOGG version 0x%X" % version)
		return PackedByteArray()

	is_encrypted = true
	print("MoggHandler: encrypted MOGG version=0x%X, attempting decryption..." % version)
	return _decrypt_mogg(mogg_data, version)

func _decrypt_mogg(mogg_data: PackedByteArray, version: int) -> PackedByteArray:
	ogg_offset = mogg_data.decode_u32(4)
	if ogg_offset >= mogg_data.size():
		push_error("MoggHandler: OGG offset (%d) beyond file (%d)" % [ogg_offset, mogg_data.size()])
		return PackedByteArray()

	# Derive CTR key
	var ctr_key: PackedByteArray
	if version == 0x0B:
		ctr_key = CTR_KEY_0B
	else:
		var hv_key: PackedByteArray
		match version:
			0x0C, 0x0D:
				hv_key = HV_KEY_0C
			0x0E:
				hv_key = HV_KEY_0E
			0x0F:
				hv_key = HV_KEY_0F
			0x10:
				hv_key = HV_KEY_10
			0x11:
				hv_key = HV_KEY_11
			_:
				push_error("MoggHandler: no HV key for version 0x%X" % version)
				return PackedByteArray()
		ctr_key = _gen_key(hv_key, mogg_data, version)
		if ctr_key.is_empty():
			push_error("MoggHandler: key derivation failed")
			return PackedByteArray()

	# Read nonce
	var hmx_header_size := mogg_data.decode_u32(16)
	var nonce_offset: int = 20 + hmx_header_size * 8
	if nonce_offset + 16 > mogg_data.size():
		push_error("MoggHandler: nonce offset out of bounds")
		return PackedByteArray()
	var nonce := mogg_data.slice(nonce_offset, nonce_offset + 16)

	print("MoggHandler: ogg_offset=%d, hmx_entries=%d, nonce_offset=%d" % [ogg_offset, hmx_header_size, nonce_offset])

	# Decrypt OGG data in-place copy using AES-128 CTR
	var encrypted := mogg_data.slice(ogg_offset)
	var decrypted := _aes_ctr_decrypt(ctr_key, nonce, encrypted)

	# Check for HMXA magic and fix up
	if decrypted.size() >= 4 and decrypted.slice(0, 4) == PackedByteArray([0x48, 0x4D, 0x58, 0x41]):
		print("MoggHandler: HMXA header detected, applying fixup")
		decrypted = _hmxa_to_ogg(decrypted, mogg_data, hmx_header_size)

	# Verify OggS magic
	if decrypted.size() < 4 or decrypted.slice(0, 4).get_string_from_ascii() != "OggS":
		push_error("MoggHandler: decryption failed — no OggS magic (got %02X %02X %02X %02X)" % [
			decrypted[0] if decrypted.size() > 0 else 0,
			decrypted[1] if decrypted.size() > 1 else 0,
			decrypted[2] if decrypted.size() > 2 else 0,
			decrypted[3] if decrypted.size() > 3 else 0])
		return PackedByteArray()

	print("MoggHandler: decryption successful! OGG size=%d bytes" % decrypted.size())
	is_encrypted = false  # Successfully decrypted
	return decrypted

func _aes_ctr_decrypt(key: PackedByteArray, nonce: PackedByteArray, data: PackedByteArray) -> PackedByteArray:
	# Process in chunks to avoid freezing and reduce memory spike
	# Each chunk = 4096 blocks = 64KB — keeps memory reasonable
	const CHUNK_BLOCKS := 4096
	var total_blocks := (data.size() + 15) / 16
	var result := data.duplicate()
	var n := nonce.duplicate()
	var aes := AESContext.new()
	var processed := 0

	while processed < total_blocks:
		var batch := mini(CHUNK_BLOCKS, total_blocks - processed)
		# Build counter blocks for this chunk
		var counter_buf := PackedByteArray()
		counter_buf.resize(batch * 16)
		for b in range(batch):
			var off := b * 16
			for i in range(16):
				counter_buf[off + i] = n[i]
			# Increment 128-bit LE
			var carry := 1
			for i in range(16):
				if carry == 0:
					break
				var s: int = n[i] + carry
				n[i] = s & 0xFF
				carry = s >> 8

		# Batch AES encrypt (native, fast)
		aes.start(AESContext.MODE_ECB_ENCRYPT, key)
		var keystream := aes.update(counter_buf)
		aes.finish()

		# XOR
		var data_offset := processed * 16
		var xor_len := mini(batch * 16, data.size() - data_offset)
		for i in range(xor_len):
			result[data_offset + i] = result[data_offset + i] ^ keystream[i]

		processed += batch

	return result

func _add_u128_le(base: PackedByteArray, value: int) -> PackedByteArray:
	## Add an integer to a 128-bit little-endian value
	var result := base.duplicate()
	var carry := value
	for i in range(16):
		if carry == 0:
			break
		var sum: int = result[i] + (carry & 0xFF)
		result[i] = sum & 0xFF
		carry = (carry >> 8) + (sum >> 8)
	return result

func _gen_key(hv_key: PackedByteArray, mogg_data: PackedByteArray, version: int) -> PackedByteArray:
	## Derive AES key from MOGG header (Xbox 360 path)
	var hmx_header_size := mogg_data.decode_u32(16)
	var base_offset: int = 20 + hmx_header_size * 8 + 16

	# Read key_mask (Xbox 360 path: offset + 32, decrypt with HV key)
	var key_mask_offset: int = base_offset + 32
	if key_mask_offset + 16 > mogg_data.size():
		push_error("MoggHandler: key_mask offset out of bounds")
		return PackedByteArray()
	var key_mask_encrypted := mogg_data.slice(key_mask_offset, key_mask_offset + 16)

	# Decrypt key_mask with AES-ECB using HV key
	var aes := AESContext.new()
	aes.start(AESContext.MODE_ECB_DECRYPT, hv_key)
	var key_mask := aes.update(key_mask_encrypted)
	aes.finish()

	# Read magic values
	var magic_a := mogg_data.decode_u32(base_offset)
	var magic_b := mogg_data.decode_u32(base_offset + 8)

	# Read key index (Xbox: index % 6 + 6)
	var key_index_offset: int = base_offset + 48
	if version == 0x11:
		key_index_offset += 8  # Skip use_new_hidden_keys field
	if key_index_offset + 8 > mogg_data.size():
		push_error("MoggHandler: key_index offset out of bounds")
		return PackedByteArray()
	var key_index_raw: int = mogg_data.decode_u64(key_index_offset)
	var key_index: int = (key_index_raw % 6) + 6  # Xbox path

	if key_index >= HIDDEN_KEYS.size():
		push_error("MoggHandler: key_index %d out of range" % key_index)
		return PackedByteArray()

	var selected_key: Array = HIDDEN_KEYS[key_index]

	# Reveal key: 14x supershuffle then XOR with masher
	var masher := _get_masher()
	var revealed := PackedByteArray()
	revealed.resize(32)
	for i in range(32):
		revealed[i] = selected_key[i]
	for _j in range(14):
		_supershuffle(revealed)
	for i in range(32):
		revealed[i] = revealed[i] ^ masher[i]

	# Convert hex-string bytes to 16-byte key
	var hex_key := _hex_string_to_bytes(revealed)

	# Grind array
	var ground := _grind_array(magic_a, magic_b, hex_key, version)

	# XOR with key_mask
	var final_key := PackedByteArray()
	final_key.resize(16)
	for i in range(16):
		final_key[i] = ground[i] ^ key_mask[i]

	print("MoggHandler: key derived (magic_a=%08X, magic_b=%08X, idx=%d)" % [magic_a, magic_b, key_index])
	return final_key

func _get_masher() -> PackedByteArray:
	var masher_word: int = 0xeb
	var result := PackedByteArray()
	result.resize(32)
	for idx in range(8):
		if idx == 0:
			masher_word = 0xeb
		# wrapping multiply and add (32-bit)
		masher_word = (masher_word * 0x19660e + 0x3c6ef35f) & 0xFFFFFFFF
		# Store as signed i32 LE
		result[idx * 4] = masher_word & 0xFF
		result[idx * 4 + 1] = (masher_word >> 8) & 0xFF
		result[idx * 4 + 2] = (masher_word >> 16) & 0xFF
		result[idx * 4 + 3] = (masher_word >> 24) & 0xFF
	return result

func _supershuffle(key: PackedByteArray) -> void:
	_shuffle1(key)
	_shuffle2(key)
	_shuffle3(key)
	_shuffle4(key)
	_shuffle5(key)
	_shuffle6(key)

func _roll(x: int) -> int:
	return (x + 0x13) % 0x20

func _shuffle1(key: PackedByteArray) -> void:
	for i in range(8):
		var offset := _roll(i * 4)
		var tmp := key[offset]; key[offset] = key[i * 4 + 2]; key[i * 4 + 2] = tmp
		offset = _roll(i * 4 + 3)
		tmp = key[offset]; key[offset] = key[i * 4 + 1]; key[i * 4 + 1] = tmp

func _shuffle2(key: PackedByteArray) -> void:
	for i in range(8):
		var tmp := key[(7 - i) * 4 + 1]; key[(7 - i) * 4 + 1] = key[i * 4 + 2]; key[i * 4 + 2] = tmp
		tmp = key[(7 - i) * 4]; key[(7 - i) * 4] = key[i * 4 + 3]; key[i * 4 + 3] = tmp

func _shuffle3(key: PackedByteArray) -> void:
	for i in range(8):
		var offset := _roll((7 - i) * 4 + 1)
		var tmp := key[offset]; key[offset] = key[i * 4 + 2]; key[i * 4 + 2] = tmp
		tmp = key[(7 - i) * 4]; key[(7 - i) * 4] = key[i * 4 + 3]; key[i * 4 + 3] = tmp

func _shuffle4(key: PackedByteArray) -> void:
	for i in range(8):
		var tmp := key[(7 - i) * 4 + 1]; key[(7 - i) * 4 + 1] = key[i * 4 + 2]; key[i * 4 + 2] = tmp
		var offset := _roll((7 - i) * 4)
		tmp = key[offset]; key[offset] = key[i * 4 + 3]; key[i * 4 + 3] = tmp

func _shuffle5(key: PackedByteArray) -> void:
	for i in range(8):
		var offset := _roll(i * 4 + 2)
		var tmp := key[(7 - i) * 4 + 1]; key[(7 - i) * 4 + 1] = key[offset]; key[offset] = tmp
		tmp = key[(7 - i) * 4]; key[(7 - i) * 4] = key[i * 4 + 3]; key[i * 4 + 3] = tmp

func _shuffle6(key: PackedByteArray) -> void:
	for i in range(8):
		var tmp := key[(7 - i) * 4 + 1]; key[(7 - i) * 4 + 1] = key[i * 4 + 2]; key[i * 4 + 2] = tmp
		var offset := _roll(i * 4 + 3)
		tmp = key[(7 - i) * 4]; key[(7 - i) * 4] = key[offset]; key[offset] = tmp

func _hex_string_to_bytes(s: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(16)
	for i in range(16):
		var hi := _ascii_digit_to_hex(s[i * 2])
		var lo := _ascii_digit_to_hex(s[i * 2 + 1])
		result[i] = (hi * 16 + lo) & 0xFF
	return result

func _ascii_digit_to_hex(h: int) -> int:
	if h >= 0x61 and h <= 0x66:  # a-f
		return h - 87
	elif h >= 0x41 and h <= 0x46:  # A-F
		return h - 0x37
	else:  # 0-9
		return (h - 0x30) & 0xFF

func _lcg(x: int) -> int:
	return (x * 0x19660d + 0x3c6ef35f) & 0xFFFFFFFF

func _grind_array(magic_a_in: int, magic_b_in: int, key_in: PackedByteArray, version: int) -> PackedByteArray:
	var key := key_in.duplicate()
	var magic_a: int = magic_a_in & 0xFFFFFFFF
	var magic_b: int = magic_b_in & 0xFFFFFFFF

	# Build array2 from magic_a
	var array2 := PackedInt32Array()
	array2.resize(256)
	var ma := magic_a
	for i in range(256):
		array2[i] = (ma & 0xFF) >> 3
		ma = _lcg(ma)

	if magic_b == 0:
		magic_b = 0x303f

	# Build shuffle order array1
	var array_used := PackedByteArray()
	array_used.resize(64)
	var array1 := PackedByteArray()
	array1.resize(64)
	var mb := magic_b
	for i in range(0x20):
		var num: int
		while true:
			mb = _lcg(mb)
			num = (mb >> 2) & 0x1f
			if array_used[num] == 0:
				break
		array1[i] = num
		array_used[num] = 1

	var array3 := array2.duplicate()

	# Build array4 from magic_b (original)
	var array4 := PackedInt32Array()
	array4.resize(256)
	var ma2 := magic_b_in & 0xFFFFFFFF
	for i in range(256):
		array4[i] = ((ma2 & 0xFF) >> 2) & 0x3f
		ma2 = _lcg(ma2)

	if version > 13:
		var num1 := magic_a_in & 0xFFFFFFFF  # num2 in rust = magic_b original, but num1 reuses magic_a
		# Actually in rust: magic_a = num2 (which is the original magic_b)
		# Let me re-read: num1 starts as magic_a (original), gets reused for the second loop
		num1 = magic_a_in & 0xFFFFFFFF
		for i in range(32, 64):
			var num: int
			while true:
				num1 = _lcg(num1)
				num = ((num1 >> 2) & 0x1f) + 0x20
				if array_used[num] == 0:
					break
			array1[i] = num
			array_used[num] = 1
		array3 = array4

	# Apply o_funcs
	for j in range(16):
		var num3: int = key[j]
		for k in range(0, 16, 2):
			var lookup_idx: int = key[k]
			var op_idx: int = array3[lookup_idx] if lookup_idx < 256 else 0
			var op: int = array1[op_idx] if op_idx < 64 else 0
			num3 = _o_func(num3, key[k + 1], op)
		key[j] = num3 & 0xFF

	return key

func _rotr8(x: int, n: int) -> int:
	x = x & 0xFF
	n = n & 7
	return ((x >> n) | (x << (8 - n))) & 0xFF

func _rotl8(x: int, n: int) -> int:
	x = x & 0xFF
	n = n & 7
	return ((x << n) | (x >> (8 - n))) & 0xFF

func _o_func(a1_in: int, a2_in: int, op: int) -> int:
	var a1: int = a1_in & 0xFF
	var a2: int = a2_in & 0xFF
	var not_a1 := 1 if a1 == 0 else 0
	var not_a2 := 1 if a2 == 0 else 0
	var ret: int
	match op:
		0: ret = a2 + _rotr8(a1, not_a2)
		1: ret = a2 + _rotr8(a1, 3)
		2: ret = a2 + _rotl8(a1, 1)
		3: ret = a2 ^ ((a1 >> (a2 & 7)) | (a1 << ((-a2) & 7))) & 0xFF
		4: ret = a2 ^ _rotl8(a1, 4)
		5: ret = a2 + (a2 ^ _rotr8(a1, 3))
		6: ret = a2 + _rotl8(a1, 2)
		7: ret = a2 + not_a1
		8: ret = a2 ^ _rotr8(a1, not_a2)
		9: ret = a2 ^ ((a2 + _rotl8(a1, 3)) & 0xFF)
		10: ret = a2 + _rotl8(a1, 3)
		11: ret = a2 + _rotl8(a1, 4)
		12: ret = a1 ^ a2
		13: ret = a2 ^ not_a1
		14: ret = a2 ^ ((a2 + _rotr8(a1, 3)) & 0xFF)
		15: ret = a2 ^ _rotl8(a1, 3)
		16: ret = a2 ^ _rotl8(a1, 2)
		17: ret = a2 + (a2 ^ _rotl8(a1, 3))
		18: ret = a2 + (a1 ^ a2)
		19: ret = a1 + a2
		20: ret = a2 ^ _rotr8(a1, 3)
		21: ret = a2 ^ ((a1 + a2) & 0xFF)
		22: ret = _rotr8(a1, not_a2)
		23: ret = a2 + _rotr8(a1, 1)
		24: ret = ((a1 >> (a2 & 7)) | (a1 << ((-a2) & 7))) & 0xFF
		25:
			if a1 == 0:
				ret = 128 if a2 == 0 else 1
			else:
				ret = 0
		26: ret = a2 + _rotr8(a1, 2)
		27: ret = a2 ^ _rotr8(a1, 1)
		28: ret = _o_func((~a1) & 0xFF, a2_in, 24)
		29: ret = a2 ^ _rotr8(a1, 2)
		30: ret = a2 + (((a1 >> (a2 & 7)) | (a1 << ((-a2) & 7))) & 0xFF)
		31: ret = a2 ^ _rotl8(a1, 1)
		32: ret = (((a1 << 8) | 170 | (a1 ^ 255)) >> 4) ^ a2
		33: ret = (((a1 ^ 255) | (a1 << 8)) >> 3) ^ a2
		34: ret = (((a1 << 8) ^ 65280 | a1) >> 2) ^ a2
		35: ret = (((a1 ^ 92) | (a1 << 8)) >> 5) ^ a2
		36: ret = (((a1 << 8) | 101 | (a1 ^ 60)) >> 2) ^ a2
		37: ret = (((a1 ^ 54) | (a1 << 8)) >> 2) ^ a2
		38: ret = (((a1 ^ 54) | (a1 << 8)) >> 4) ^ a2
		39: ret = (((a1 ^ 92) | (a1 << 8) | 54) >> 1) ^ a2
		40: ret = (((a1 ^ 255) | (a1 << 8)) >> 5) ^ a2
		41: ret = ((((~a1) & 0xFF) << 8 | a1) >> 6) ^ a2
		42: ret = (((a1 ^ 92) | (a1 << 8)) >> 3) ^ a2
		43: ret = (((a1 ^ 60) | 101 | (a1 << 8)) >> 5) ^ a2
		44: ret = (((a1 ^ 54) | (a1 << 8)) >> 1) ^ a2
		45: ret = (((a1 ^ 101) | (a1 << 8) | 60) >> 6) ^ a2
		46: ret = (((a1 ^ 92) | (a1 << 8)) >> 2) ^ a2
		47: ret = (((a2 ^ 170) | (a2 << 8) | 255) >> 3) ^ a1
		48: ret = (((a1 ^ 99) | (a1 << 8) | 92) >> 6) ^ a2
		49: ret = (((a1 ^ 92) | (a1 << 8) | 54) >> 7) ^ a2
		50: ret = (((a1 ^ 92) | (a1 << 8)) >> 6) ^ a2
		51: ret = (((a1 << 8) ^ 65280 | a1) >> 3) ^ a2
		52: ret = (((a1 ^ 255) | (a1 << 8)) >> 6) ^ a2
		53: ret = (((a1 << 8) ^ 65280 | a1) >> 5) ^ a2
		54: ret = (((a1 ^ 60) | 101 | (a1 << 8)) >> 4) ^ a2
		55: ret = (((a1 ^ 99) | (a1 << 8) | 92) >> 3) ^ a2
		56: ret = (((a1 ^ 99) | (a1 << 8) | 92) >> 5) ^ a2
		57: ret = (((a1 ^ 175) | (a1 << 8) | 250) >> 5) ^ a2
		58: ret = (((a1 ^ 92) | (a1 << 8) | 54) >> 5) ^ a2
		59: ret = (((a1 ^ 92) | (a1 << 8) | 54) >> 3) ^ a2
		60: ret = (((a1 ^ 54) | (a1 << 8)) >> 3) ^ a2
		61: ret = (((a1 ^ 99) | (a1 << 8) | 92) >> 4) ^ a2
		62: ret = (((a1 ^ 255) | (a1 << 8) | 175) >> 6) ^ a2
		63: ret = (((a1 ^ 255) | (a1 << 8)) >> 2) ^ a2
		_: ret = 0
	return ret & 0xFF

func _hmxa_to_ogg(decrypted: PackedByteArray, mogg_data: PackedByteArray, num_entries: int) -> PackedByteArray:
	var result := decrypted.duplicate()
	var base_offset: int = 20 + num_entries * 8 + 16
	var magic_a := mogg_data.decode_u32(base_offset)
	var magic_b := mogg_data.decode_u32(base_offset + 8)

	var magic_hash_a := _lcg(_lcg(magic_a ^ 0x5c5c5c5c))
	var magic_hash_b := _lcg(magic_b ^ 0x36363636)

	# Replace HMXA with OggS
	result[0] = 0x4f; result[1] = 0x67; result[2] = 0x67; result[3] = 0x53

	# XOR at offset 12 (4 bytes BE)
	if result.size() >= 16:
		var val_a := (result[12] << 24) | (result[13] << 16) | (result[14] << 8) | result[15]
		val_a = val_a ^ (magic_hash_a & 0xFFFFFFFF)
		result[12] = (val_a >> 24) & 0xFF
		result[13] = (val_a >> 16) & 0xFF
		result[14] = (val_a >> 8) & 0xFF
		result[15] = val_a & 0xFF

	# XOR at offset 20 (4 bytes BE)
	if result.size() >= 24:
		var val_b := (result[20] << 24) | (result[21] << 16) | (result[22] << 8) | result[23]
		val_b = val_b ^ (magic_hash_b & 0xFFFFFFFF)
		result[20] = (val_b >> 24) & 0xFF
		result[21] = (val_b >> 16) & 0xFF
		result[22] = (val_b >> 8) & 0xFF
		result[23] = val_b & 0xFF

	return result

func save_ogg_to_file(mogg_data: PackedByteArray, output_path: String) -> bool:
	var version := mogg_data.decode_u32(0) if mogg_data.size() >= 4 else 0

	# For encrypted MOGGs, use Python script (native AES speed)
	if version >= 0x0B and version <= 0x11:
		return _decrypt_via_python(mogg_data, output_path)

	# Unencrypted: extract directly
	var ogg := extract_ogg(mogg_data)
	if ogg.is_empty():
		return false

	if ogg.size() >= 4:
		var magic := ogg.slice(0, 4).get_string_from_ascii()
		if magic != "OggS":
			push_error("MoggHandler: extracted data is not valid OGG (magic='%s')" % magic)
			return false

	var dir_path := output_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("MoggHandler: cannot write to %s" % output_path)
		return false
	file.store_buffer(ogg)
	file.close()
	print("MoggHandler: OGG saved to %s (%d bytes)" % [output_path, ogg.size()])
	return true

func _decrypt_via_python(mogg_data: PackedByteArray, output_path: String) -> bool:
	# On Android use NativeAudioDecoder plugin (javax.crypto AES — native speed)
	if OS.get_name() == "Android":
		return _decrypt_via_plugin(mogg_data, output_path)

	# Write raw MOGG to temp file
	var tmp_dir := OS.get_user_data_dir() + "/tmp"
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	var tmp_mogg := tmp_dir + "/temp_encrypted.mogg"

	var f := FileAccess.open(tmp_mogg, FileAccess.WRITE)
	if f == null:
		push_error("MoggHandler: cannot write temp MOGG")
		return false
	f.store_buffer(mogg_data)
	f.close()

	# Find Python script — try multiple locations
	var script_path := ""
	# In editor: res://tools/ works directly
	if FileAccess.file_exists("res://tools/mogg_decrypt.py"):
		script_path = ProjectSettings.globalize_path("res://tools/mogg_decrypt.py")
	else:
		# Exported build: script should be next to executable
		script_path = OS.get_executable_path().get_base_dir().path_join("tools/mogg_decrypt.py")
	if not FileAccess.file_exists(script_path) and script_path != ProjectSettings.globalize_path("res://tools/mogg_decrypt.py"):
		# Last resort
		script_path = ProjectSettings.globalize_path("res://tools/mogg_decrypt.py")

	# Ensure output directory exists
	var dir_path := output_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)

	# Globalize output path if it's user://
	var global_output := output_path
	if output_path.begins_with("user://"):
		global_output = ProjectSettings.globalize_path(output_path)

	# Run Python
	var output := []
	var python_cmd := "python"
	if OS.get_name() == "Linux":
		python_cmd = "python3"

	print("MoggHandler: decrypting via Python: %s -> %s" % [tmp_mogg, global_output])
	var exit_code := OS.execute(python_cmd, [script_path, tmp_mogg, global_output], output, true)

	# Clean up temp file
	DirAccess.remove_absolute(tmp_mogg)

	if exit_code != 0:
		var err_msg := "\n".join(output) if output.size() > 0 else "unknown error"
		push_error("MoggHandler: Python decrypt failed (exit %d): %s" % [exit_code, err_msg])
		return false

	# Verify output exists and has OggS magic
	var check := FileAccess.open(global_output, FileAccess.READ)
	if check == null:
		push_error("MoggHandler: Python produced no output file")
		return false
	var magic := check.get_buffer(4)
	var file_size := check.get_length()
	check.close()

	if magic.get_string_from_ascii() != "OggS":
		push_error("MoggHandler: Python output is not valid OGG")
		DirAccess.remove_absolute(global_output)
		return false

	print("MoggHandler: Python decryption successful! OGG size=%d bytes" % file_size)
	is_encrypted = false
	return true

func _decrypt_via_plugin(mogg_data: PackedByteArray, output_path: String) -> bool:
	# Use NativeAudioDecoder Kotlin plugin for fast AES decryption on Android
	if not Engine.has_singleton("NativeAudioDecoder"):
		push_error("MoggHandler: NativeAudioDecoder plugin not available, using GDScript fallback")
		return _decrypt_fallback_gdscript(mogg_data, output_path)

	# Write MOGG to temp file (plugin needs file paths)
	var tmp_dir := OS.get_user_data_dir() + "/tmp"
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	var tmp_mogg := tmp_dir + "/temp_encrypted.mogg"

	var f := FileAccess.open(tmp_mogg, FileAccess.WRITE)
	if f == null:
		push_error("MoggHandler: cannot write temp MOGG for plugin")
		return _decrypt_fallback_gdscript(mogg_data, output_path)
	f.store_buffer(mogg_data)
	f.close()

	# Globalize output path
	var global_output := output_path
	if output_path.begins_with("user://"):
		global_output = ProjectSettings.globalize_path(output_path)
	DirAccess.make_dir_recursive_absolute(global_output.get_base_dir())

	var plugin = Engine.get_singleton("NativeAudioDecoder")
	print("MoggHandler: decrypting via plugin: %s -> %s" % [tmp_mogg, global_output])
	var error: String = plugin.decryptMogg(tmp_mogg, global_output)

	# Clean up temp
	DirAccess.remove_absolute(tmp_mogg)

	if error != "":
		push_error("MoggHandler: plugin decrypt failed: %s" % error)
		return false

	is_encrypted = false
	print("MoggHandler: plugin decryption successful!")
	return true

func _decrypt_fallback_gdscript(mogg_data: PackedByteArray, output_path: String) -> bool:
	# GDScript-based decryption (slow but works on Android worker thread)
	var ogg := _decrypt_mogg(mogg_data, mogg_data.decode_u32(0))
	if ogg.is_empty():
		return false
	if ogg.size() < 4 or ogg.slice(0, 4).get_string_from_ascii() != "OggS":
		push_error("MoggHandler: GDScript decrypt produced invalid OGG")
		return false
	var dir_path := output_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("MoggHandler: cannot write to %s" % output_path)
		return false
	file.store_buffer(ogg)
	file.close()
	print("MoggHandler: GDScript decryption saved to %s (%d bytes)" % [output_path, ogg.size()])
	is_encrypted = false
	return true
