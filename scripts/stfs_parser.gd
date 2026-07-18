class_name StfsParser
extends RefCounted

## Parses Xbox 360 STFS container files (CON/LIVE/PIRS) used by Rock Band.
## Extracts embedded files: songs.dta, .mogg, .mid, album art.

var files: Dictionary = {}  # path -> PackedByteArray
var _data: PackedByteArray
var _table_size_shift: int = 0
var _table_spacing: Array = []
var _allocated_count: int = 0
var _file_table_block: int = 0
var _file_table_block_count: int = 0

const SPACING_SHIFT0 := [0xAB, 0x718F, 0xFE7DA]
const SPACING_SHIFT1 := [0xAC, 0x723A, 0xFD00B]

func load_stfs(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("StfsParser: cannot open %s" % path)
		return false
	_data = file.get_buffer(file.get_length())
	file.close()
	return parse_data()

func load_stfs_from_buffer(data: PackedByteArray) -> bool:
	_data = data
	return parse_data()

func parse_data() -> bool:
	if _data.size() < 0xC000:
		push_error("StfsParser: file too small (%d bytes)" % _data.size())
		return false

	# Check magic
	var magic := _data.slice(0, 4).get_string_from_ascii()
	if magic != "CON " and magic != "LIVE" and magic != "PIRS":
		push_error("StfsParser: invalid magic '%s'" % magic)
		return false
	print("StfsParser: magic = %s" % magic)

	# Read metadata — header size at 0x340 (4 bytes BE)
	var header_size := _read_u32_be(0x340)

	# Determine table size shift
	var adjusted := (header_size + 0xFFF) & 0xFFFFF000
	if (adjusted >> 12) == 0xB:
		_table_size_shift = 0
		_table_spacing = SPACING_SHIFT0
	else:
		_table_size_shift = 1
		_table_spacing = SPACING_SHIFT1

	# Volume descriptor (STFS) at 0x379
	# Descriptor size at 0x379, block separation at 0x37B
	_file_table_block_count = _read_u16_le(0x37C)
	_file_table_block = _read_u24_le(0x37E)
	_allocated_count = _read_u32_be(0x395)

	print("StfsParser: shift=%d, ft_block=%d, ft_count=%d, alloc=%d" % [
		_table_size_shift, _file_table_block, _file_table_block_count, _allocated_count
	])

	# Read file table
	var entries := _read_file_table()
	print("StfsParser: found %d file entries" % entries.size())

	# Build directory tree and extract files
	files.clear()
	for entry in entries:
		if entry["is_dir"]:
			continue
		var full_path := _build_path(entry, entries)
		print("StfsParser: extracting '%s' (%d bytes)" % [full_path, entry["size"]])
		var file_data := _extract_file(entry)
		if file_data.size() > 0:
			files[full_path] = file_data

	print("StfsParser: extracted %d files" % files.size())
	return files.size() > 0

func _fix_block_num(block: int) -> int:
	## Adjusts a logical data block number to a raw disk block number
	## by accounting for interleaved hash table blocks.
	var adjusted := block
	if block >= 0xAA:
		adjusted += ((block / 0xAA) + 1) << _table_size_shift
	if block >= 0x70E4:
		adjusted += ((block / 0x70E4) + 1) << _table_size_shift
	return adjusted

func _read_raw_block(raw_block: int, length: int = 0x1000) -> PackedByteArray:
	## Read a block using a raw (disk) block number — no fix applied.
	var offset := 0xC000 + raw_block * 0x1000
	if offset + length > _data.size():
		return PackedByteArray()
	return _data.slice(offset, offset + length)

func _read_data_block(logical_block: int, length: int = 0x1000) -> PackedByteArray:
	## Read a data block — applies fix_block_num to skip hash tables.
	return _read_raw_block(_fix_block_num(logical_block), length)

func _get_hash_entry_for_block(block: int, table_offset: int = 0) -> Dictionary:
	## Get the hash entry for a logical data block — tells us the next block.
	var record_index := block % 0xAA
	# Calculate which hash table block contains this record
	var table_num: int = (block / 0xAA) * int(_table_spacing[0])
	if block >= 0xAA:
		table_num += ((block / 0x70E4) + 1) << _table_size_shift
	if block >= 0x70E4:
		table_num += 1 << _table_size_shift
	# Adjust to point at the first hash table (offset from data blocks)
	table_num += table_offset - (1 << _table_size_shift)

	# Hash tables use raw block numbers — no fix_block_num needed
	var hash_data := _read_raw_block(table_num)
	if hash_data.size() < (record_index + 1) * 0x18:
		return {"next_block": -1, "info": 0}

	var rec_off := record_index * 0x18
	var info: int = hash_data[rec_off + 0x14]
	# Next block is 24-bit big-endian at offset +0x15
	var next_block := (hash_data[rec_off + 0x15] << 16) | (hash_data[rec_off + 0x16] << 8) | hash_data[rec_off + 0x17]

	# If shift1 and info < 0x80, try alternate table (offset + 1)
	if _table_size_shift > 0 and info < 0x80:
		return _get_hash_entry_for_block(block, table_offset + 1)

	return {"next_block": next_block, "info": info}

func _read_file_table() -> Array:
	var entries: Array = []
	var current_block := _file_table_block
	var blocks_read := 0

	var all_data := PackedByteArray()

	while blocks_read < _file_table_block_count:
		var block_data := _read_data_block(current_block)
		if block_data.is_empty():
			break
		all_data.append_array(block_data)

		# Follow chain
		var hash := _get_hash_entry_for_block(current_block)
		current_block = hash["next_block"]
		blocks_read += 1

		if current_block <= 0 or current_block >= _allocated_count:
			break

	# Parse 0x40-byte entries
	var pos := 0
	while pos + 0x40 <= all_data.size():
		var name_bytes := all_data.slice(pos, pos + 0x28)
		# Find null terminator
		var name_end := 0
		while name_end < 0x28 and name_bytes[name_end] != 0:
			name_end += 1
		if name_end == 0:
			break  # Empty entry = end of table

		var fname := name_bytes.slice(0, name_end).get_string_from_utf8()
		var flags: int = all_data[pos + 0x28]
		var is_dir := (flags & 0x80) != 0

		# Num blocks: 24-bit LE at pos+0x29
		var num_blocks := all_data[pos + 0x29] | (all_data[pos + 0x2A] << 8) | (all_data[pos + 0x2B] << 16)

		# First block: 24-bit LE at pos+0x2F
		var first_block := all_data[pos + 0x2F] | (all_data[pos + 0x30] << 8) | (all_data[pos + 0x31] << 16)

		# Path index: 16-bit BE at pos+0x32
		var path_index := (all_data[pos + 0x32] << 8) | all_data[pos + 0x33]
		if path_index >= 0x8000:
			path_index -= 0x10000  # Signed

		# Size: 32-bit BE at pos+0x34
		var file_size := _read_u32_be_from(all_data, pos + 0x34)

		entries.append({
			"name": fname,
			"is_dir": is_dir,
			"num_blocks": num_blocks,
			"first_block": first_block,
			"path_index": path_index,
			"size": file_size,
		})

		pos += 0x40

	return entries

func _build_path(entry: Dictionary, entries: Array) -> String:
	var parts: Array[String] = [entry["name"]]
	var idx: int = entry["path_index"]
	var safety := 0
	while idx >= 0 and idx < entries.size() and safety < 20:
		parts.push_front(entries[idx]["name"])
		idx = entries[idx]["path_index"]
		safety += 1
	return "/".join(parts)

func _extract_file(entry: Dictionary) -> PackedByteArray:
	var result := PackedByteArray()
	var remaining: int = entry["size"]
	var block: int = entry["first_block"]
	var info := 0x80
	var safety := 0

	while remaining > 0 and block >= 0 and block < _allocated_count and info >= 0x80 and safety < 100000:
		var read_len := mini(0x1000, remaining)
		var block_data := _read_data_block(block, read_len)
		if block_data.is_empty():
			break
		result.append_array(block_data)
		remaining -= read_len

		var hash := _get_hash_entry_for_block(block)
		block = hash["next_block"]
		info = hash["info"]
		safety += 1

	return result

# --- Helpers ---
func _read_u32_be(offset: int) -> int:
	return (_data[offset] << 24) | (_data[offset + 1] << 16) | (_data[offset + 2] << 8) | _data[offset + 3]

func _read_u32_be_from(data: PackedByteArray, offset: int) -> int:
	return (data[offset] << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3]

func _read_u16_le(offset: int) -> int:
	return _data[offset] | (_data[offset + 1] << 8)

func _read_u24_le(offset: int) -> int:
	return _data[offset] | (_data[offset + 1] << 8) | (_data[offset + 2] << 16)

func _read_u32_le(offset: int) -> int:
	return _data.decode_u32(offset)

# --- Query helpers ---
func get_dta_text() -> String:
	for fname in files:
		if fname.to_lower().ends_with("songs.dta") or fname.to_lower().ends_with(".dta"):
			return files[fname].get_string_from_utf8()
	return ""

func get_mogg_data() -> PackedByteArray:
	for fname in files:
		if fname.to_lower().ends_with(".mogg"):
			return files[fname]
	return PackedByteArray()

func get_midi_data() -> PackedByteArray:
	for fname in files:
		if fname.to_lower().ends_with(".mid"):
			return files[fname]
	return PackedByteArray()

func get_album_art_data() -> PackedByteArray:
	for fname in files:
		var fl: String = (fname as String).to_lower()
		if fl.ends_with(".png_xbox") or fl.ends_with(".png") or fl.ends_with(".jpg"):
			return files[fname]
	return PackedByteArray()
