class_name SngLoader
extends RefCounted

var metadata: Dictionary = {}
var files: Dictionary = {}  # name -> PackedByteArray (decrypted)

func load_sng(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SngLoader: cannot open %s" % path)
		return false

	var data := file.get_buffer(file.get_length())
	file.close()

	# --- Magic check ---
	if data.size() < 26:
		push_error("SngLoader: file too small")
		return false

	var magic := data.slice(0, 6).get_string_from_ascii()
	if magic != "SNGPKG":
		push_error("SngLoader: not a .sng file (magic=%s)" % magic)
		return false

	var pos := 6 + 4  # skip magic + version
	var mask := data.slice(pos, pos + 16)
	pos += 16

	# --- Metadata ---
	var meta_len := _read_u64(data, pos)
	pos += 8
	var meta_end := pos + meta_len
	var kv_count := _read_u64(data, pos)
	pos += 8

	for i in range(kv_count):
		var klen := _read_i32(data, pos)
		pos += 4
		var key := data.slice(pos, pos + klen).get_string_from_utf8()
		pos += klen
		var vlen := _read_i32(data, pos)
		pos += 4
		var val := data.slice(pos, pos + vlen).get_string_from_utf8()
		pos += vlen
		metadata[key] = val

	pos = meta_end

	# --- File index ---
	pos += 8  # skip index section length
	var fcount := _read_u64(data, pos)
	pos += 8

	var file_entries: Array = []
	for i in range(fcount):
		var nlen: int = data[pos]
		pos += 1
		var fname := data.slice(pos, pos + nlen).get_string_from_utf8()
		pos += nlen
		var flen := _read_u64(data, pos)
		pos += 8
		var foff := _read_u64(data, pos)
		pos += 8
		file_entries.append({"name": fname, "size": flen, "offset": foff})

	# --- Decrypt files ---
	for entry in file_entries:
		var fname: String = entry["name"]
		var flen: int = entry["size"]
		var foff: int = entry["offset"]
		var raw := data.slice(foff, foff + flen)
		var clear := PackedByteArray()
		clear.resize(flen)
		for j in range(flen):
			clear[j] = raw[j] ^ (mask[j % 16] ^ (j & 0xFF))
		files[fname] = clear

	return true

func get_chart_text() -> String:
	for fname in files:
		if fname.ends_with(".chart"):
			return files[fname].get_string_from_utf8()
	return ""

func get_midi_data() -> PackedByteArray:
	for fname in files:
		if fname.to_lower().ends_with(".mid"):
			return files[fname]
	return PackedByteArray()

func has_chart() -> bool:
	for fname in files:
		if fname.ends_with(".chart"):
			return true
	return false

func has_midi() -> bool:
	for fname in files:
		if fname.to_lower().ends_with(".mid"):
			return true
	return false

func get_album_art_data() -> PackedByteArray:
	for fname in files:
		var fl: String = fname.to_lower()
		if fl == "album.jpg" or fl == "album.png" or fl == "cover.jpg" or fl == "cover.png":
			return files[fname]
	# Fallback: any image file
	for fname in files:
		var fl: String = fname.to_lower()
		if fl.ends_with(".jpg") or fl.ends_with(".png") or fl.ends_with(".jpeg"):
			return files[fname]
	return PackedByteArray()

func get_audio_data(preferred: String = "song.opus") -> PackedByteArray:
	if files.has(preferred):
		return files[preferred]
	# fallback: any audio file
	for fname in files:
		if fname.ends_with(".opus") or fname.ends_with(".ogg") or fname.ends_with(".mp3"):
			return files[fname]
	return PackedByteArray()

func get_audio_filename() -> String:
	# Prefer song.opus/ogg/mp3 first
	for ext in [".opus", ".ogg", ".mp3"]:
		if files.has("song" + ext):
			return "song" + ext
	# Fallback: any audio file
	for fname in files:
		if fname.ends_with(".opus") or fname.ends_with(".ogg") or fname.ends_with(".mp3"):
			return fname
	return ""

func get_audio_filenames() -> Array[String]:
	var result: Array[String] = []
	for fname in files:
		if fname.ends_with(".opus") or fname.ends_with(".ogg") or fname.ends_with(".mp3"):
			result.append(fname)
	return result

func extract_to_dir(dir_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir_path)
	for fname in files:
		var out_path := dir_path.path_join(fname)
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f:
			f.store_buffer(files[fname])
			f.close()

func _read_u64(data: PackedByteArray, pos: int) -> int:
	return data.decode_u64(pos)

func _read_i32(data: PackedByteArray, pos: int) -> int:
	return data.decode_s32(pos)
