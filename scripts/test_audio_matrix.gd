extends SceneTree

# Test Matrix — Adım 6
# a) opus'lu .sng (Bring Me to Life)
# b) ogg'lu dosya (yoksa oluştur)
# c) bozuk/uzantısız ses dosyası (hata yolunu test)
# d) .mid'li şarkı (Adım 7 için — sonra eklenir)

const SngLoaderScript = preload("res://scripts/sng_loader.gd")

var _test_results: Array[String] = []

func _init() -> void:
	print("=" .repeat(60))
	print("SES YÜKLEME TEST MATRİSİ")
	print("=" .repeat(60))
	print("AudioStreamOpus available: %s" % str(ClassDB.class_exists("AudioStreamOpus")))
	print("Project mix rate: %d Hz" % int(AudioServer.get_mix_rate()))
	print("")

	_test_a_opus_sng()
	_test_b_ogg()
	_test_c_corrupt()

	print("")
	print("=" .repeat(60))
	print("TEST SONUÇLARI:")
	for r in _test_results:
		print("  %s" % r)
	print("=" .repeat(60))
	quit(0)

func _test_a_opus_sng() -> void:
	print("--- TEST A: Opus'lu .sng (Bring Me to Life) ---")
	var sng_path := "res://songs/Evanescence - Bring Me to Life (Add Keyboard) (Harmonix; Austin Tomlinson).sng"
	var loader = SngLoaderScript.new()
	if not loader.load_sng(sng_path):
		_test_results.append("[A] FAIL — .sng yüklenemedi")
		return

	var tmp := "user://test_matrix_a"
	DirAccess.make_dir_recursive_absolute(tmp)
	loader.extract_to_dir(tmp)

	# List extracted files
	var audio_files: Array[String] = []
	var dir := DirAccess.open(tmp)
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir():
				print("  Extracted: %s" % fname)
				var fl := fname.to_lower()
				if fl.ends_with(".opus") or fl.ends_with(".ogg") or fl.ends_with(".mp3"):
					audio_files.append(fname)
			fname = dir.get_next()
		dir.list_dir_end()

	print("  Audio files: %s" % str(audio_files))

	# Try loading each audio file
	var loaded := 0
	for af: String in audio_files:
		var stream := _try_load(tmp.path_join(af))
		if stream:
			loaded += 1

	if loaded > 0:
		_test_results.append("[A] OK — %d/%d ses dosyası yüklendi (opus)" % [loaded, audio_files.size()])
	else:
		_test_results.append("[A] FAIL — hiçbir ses dosyası yüklenemedi")

func _test_b_ogg() -> void:
	print("--- TEST B: OGG dosyası ---")
	# Check if we have any ogg file in songs/
	var ogg_found := false
	var test_dir := "user://test_matrix_a"  # Reuse extracted files
	var dir := DirAccess.open(test_dir)
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.to_lower().ends_with(".ogg"):
				ogg_found = true
				print("  Found OGG: %s" % fname)
				var stream := _try_load(test_dir.path_join(fname))
				if stream:
					_test_results.append("[B] OK — OGG yüklendi: %s" % fname)
				else:
					_test_results.append("[B] FAIL — OGG yüklenemedi: %s" % fname)
			fname = dir.get_next()
		dir.list_dir_end()

	if not ogg_found:
		# No OGG available — note this
		_test_results.append("[B] SKIP — OGG dosyası bulunamadı (ffmpeg ile test dosyası oluşturulması gerekir)")
		print("  No OGG files found. To create test OGG:")
		print("  ffmpeg -i song.opus -c:a libvorbis -q:a 5 song_test.ogg")

func _test_c_corrupt() -> void:
	print("--- TEST C: Bozuk/uzantısız ses dosyası ---")
	# Create a corrupt test file
	var corrupt_dir := "user://test_matrix_c"
	DirAccess.make_dir_recursive_absolute(corrupt_dir)

	# Write corrupt data with .ogg extension
	var corrupt_path := corrupt_dir.path_join("corrupt.ogg")
	var f := FileAccess.open(corrupt_path, FileAccess.WRITE)
	if f:
		f.store_buffer(PackedByteArray([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x00, 0x00, 0x00]))
		f.close()

	# Write a file with unknown extension
	var unknown_path := corrupt_dir.path_join("audio.wav")
	var f2 := FileAccess.open(unknown_path, FileAccess.WRITE)
	if f2:
		f2.store_buffer(PackedByteArray([0x52, 0x49, 0x46, 0x46]))  # RIFF header
		f2.close()

	# Write extensionless file
	var noext_path := corrupt_dir.path_join("audiofile")
	var f3 := FileAccess.open(noext_path, FileAccess.WRITE)
	if f3:
		f3.store_buffer(PackedByteArray([0x00, 0x01, 0x02, 0x03]))
		f3.close()

	# Test corrupt .ogg
	print("  Testing corrupt.ogg...")
	var s1 := _try_load(corrupt_path)
	if s1 == null:
		_test_results.append("[C1] OK — bozuk OGG doğru şekilde reddedildi")
	else:
		_test_results.append("[C1] WARN — bozuk OGG yüklenmiş gibi görünüyor")

	# Test unknown extension
	print("  Testing audio.wav (unsupported extension)...")
	var s2 := _try_load(unknown_path)
	if s2 == null:
		_test_results.append("[C2] OK — desteklenmeyen uzantı doğru şekilde reddedildi")
	else:
		_test_results.append("[C2] WARN — desteklenmeyen uzantı yüklenmiş gibi görünüyor")

	# Test extensionless file
	print("  Testing extensionless file...")
	var s3 := _try_load(noext_path)
	if s3 == null:
		_test_results.append("[C3] OK — uzantısız dosya doğru şekilde reddedildi")
	else:
		_test_results.append("[C3] WARN — uzantısız dosya yüklenmiş gibi görünüyor")

func _try_load(path: String) -> AudioStream:
	var fname := path.get_file()
	var ext := fname.get_extension().to_lower()
	var start_ms := Time.get_ticks_msec()
	var stream: AudioStream = null

	if ext == "ogg":
		# Check OpusHead magic
		var probe := FileAccess.open(path, FileAccess.READ)
		if probe:
			var header := probe.get_buffer(mini(40, probe.get_length()))
			probe.close()
			var has_opus_head := false
			for i in range(header.size() - 7):
				if header[i] == 0x4F and header[i+1] == 0x70 and header[i+2] == 0x75 and header[i+3] == 0x73 \
					and header[i+4] == 0x48 and header[i+5] == 0x65 and header[i+6] == 0x61 and header[i+7] == 0x64:
					has_opus_head = true
					break
			if has_opus_head:
				stream = _load_opus(path)
				var elapsed := Time.get_ticks_msec() - start_ms
				print("  LOAD [%s] ext=%s loader=opus(ogg) elapsed=%dms result=%s" % [fname, ext, elapsed, "OK" if stream else "FAIL"])
				return stream
		stream = AudioStreamOggVorbis.load_from_file(path)
		var elapsed := Time.get_ticks_msec() - start_ms
		print("  LOAD [%s] ext=%s loader=OggVorbis elapsed=%dms result=%s" % [fname, ext, elapsed, "OK" if stream else "FAIL"])
	elif ext == "mp3":
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var mp3 := AudioStreamMP3.new()
			mp3.data = f.get_buffer(f.get_length())
			f.close()
			stream = mp3
		var elapsed := Time.get_ticks_msec() - start_ms
		print("  LOAD [%s] ext=%s loader=MP3 elapsed=%dms result=%s" % [fname, ext, elapsed, "OK" if stream else "FAIL"])
	elif ext == "opus":
		stream = _load_opus(path)
		var elapsed := Time.get_ticks_msec() - start_ms
		print("  LOAD [%s] ext=%s loader=Opus elapsed=%dms result=%s" % [fname, ext, elapsed, "OK" if stream else "FAIL"])
	else:
		var elapsed := Time.get_ticks_msec() - start_ms
		print("  LOAD [%s] ext=%s loader=NONE elapsed=%dms result=UNSUPPORTED" % [fname, ext, elapsed])

	return stream

func _load_opus(path: String) -> AudioStream:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var data := f.get_buffer(f.get_length())
	f.close()
	if not ClassDB.class_exists("AudioStreamOpus"):
		push_error("AudioStreamOpus class not found")
		return null
	var s = ClassDB.instantiate("AudioStreamOpus")
	if s == null:
		return null
	s.set("data", data)
	return s
