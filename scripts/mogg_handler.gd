class_name MoggHandler
extends RefCounted

## Handles Rock Band .mogg files.
## MOGG = header + OGG Vorbis audio data (multi-channel).
## Unencrypted MOGG has version 0x0A at offset 0.

var is_encrypted: bool = false
var ogg_offset: int = 0
var channel_count: int = 0

func extract_ogg(mogg_data: PackedByteArray) -> PackedByteArray:
	if mogg_data.size() < 8:
		push_error("MoggHandler: data too small")
		return PackedByteArray()

	# Version at offset 0 (32-bit LE)
	var version := mogg_data.decode_u32(0)
	if version != 0x0A:
		is_encrypted = true
		push_error("MoggHandler: encrypted MOGG (version=0x%X), cannot decode" % version)
		return PackedByteArray()

	# OGG data offset at offset 4 (32-bit LE)
	ogg_offset = mogg_data.decode_u32(4)
	if ogg_offset >= mogg_data.size():
		push_error("MoggHandler: OGG offset (%d) beyond file size (%d)" % [ogg_offset, mogg_data.size()])
		return PackedByteArray()

	print("MoggHandler: version=0x%X, ogg_offset=%d, ogg_size=%d" % [version, ogg_offset, mogg_data.size() - ogg_offset])

	# Extract OGG payload
	return mogg_data.slice(ogg_offset)

func save_ogg_to_file(mogg_data: PackedByteArray, output_path: String) -> bool:
	var ogg := extract_ogg(mogg_data)
	if ogg.is_empty():
		return false

	# Verify OGG magic
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
