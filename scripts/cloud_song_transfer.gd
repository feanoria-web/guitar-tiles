extends Node

## Uploads a song once to the private Cloudflare R2 relay and downloads it on
## guests. Firebase ID tokens remain the source of room authorization.

signal progress_changed(progress: float, detail: String, active: bool)

const CHUNK_BYTES := 4 * 1024 * 1024
const MAX_SONG_BYTES := 512 * 1024 * 1024
const MAX_FILES := 256
const MANIFEST_WAIT_SECONDS := 90
const MANIFEST_RETRY_SECONDS := 2.0
const USER_SONGS_DIR := "user://songs"
const TEMP_DIR := "user://cloud_song_downloads"

var _base_url := ""
var _operation_generation := 0


func configure(base_url: String) -> void:
	_base_url = base_url.strip_edges().trim_suffix("/")


func is_configured() -> bool:
	return _base_url.begins_with("https://")


func cancel() -> void:
	_operation_generation += 1


func upload_song(
		source_song: Dictionary,
		fingerprint: String,
		room_code: String,
		id_token: String,
) -> Dictionary:
	if not is_configured():
		return _error("Cloudflare Worker adresi ayarlanmamış.")
	var generation := _begin_operation()
	var manifest := _build_upload_manifest(source_song, fingerprint)
	if manifest.is_empty():
		return _error("Şarkı dosyaları buluta yüklenmek için hazırlanamadı.")

	progress_changed.emit(0.0, I18n.t("song_cloud_preparing"), true)
	var manifest_url := _song_url(room_code, fingerprint) + "/manifest"
	var prepare := await _request_json(
		manifest_url, HTTPClient.METHOD_POST, manifest, id_token)
	if not _is_current(generation):
		return _error("İşlem iptal edildi.", true)
	if not bool(prepare.get("ok", false)):
		return _error(_response_error(prepare, "Bulut uploadı başlatılamadı."))
	var prepare_data: Dictionary = prepare.get("data", {})
	if bool(prepare_data.get("already_ready", false)):
		progress_changed.emit(1.0, I18n.t("song_cloud_ready"), false)
		return {"ok": true, "already_ready": true}

	var total_size := int(manifest.get("total_size", 0))
	var uploaded := 0
	var files: Array = manifest.get("files", [])
	for file_index in range(files.size()):
		var file_info: Dictionary = files[file_index]
		var source_path := String(file_info.get("source_path", ""))
		var source := FileAccess.open(source_path, FileAccess.READ)
		if source == null:
			return _error("Şarkı dosyası upload sırasında açılamadı.")
		var chunk_count := int(file_info.get("chunk_count", 0))
		for chunk_index in range(chunk_count):
			if not _is_current(generation):
				source.close()
				return _error("İşlem iptal edildi.", true)
			var remaining := int(file_info.get("size", 0)) \
				- chunk_index * CHUNK_BYTES
			var chunk := source.get_buffer(mini(CHUNK_BYTES, remaining))
			if chunk.is_empty() or chunk.size() != mini(CHUNK_BYTES, remaining):
				source.close()
				return _error("Şarkı dosyası okunurken hata oluştu.")
			var chunk_url := "%s/files/%d/chunks/%d" % [
				_song_url(room_code, fingerprint), file_index, chunk_index]
			var response := await _request_bytes(
				chunk_url, HTTPClient.METHOD_PUT, chunk, id_token)
			if not _is_current(generation):
				source.close()
				return _error("İşlem iptal edildi.", true)
			if not bool(response.get("ok", false)):
				source.close()
				return _error(_response_error(
					response, "Şarkı parçası Cloudflare'a yüklenemedi."))
			uploaded += chunk.size()
			progress_changed.emit(
				float(uploaded) / maxf(1.0, float(total_size)),
				I18n.t("song_cloud_uploading", [int(
					float(uploaded) * 100.0 / maxf(1.0, float(total_size)))]),
				true,
			)
		source.close()

	var complete := await _request_json(
		_song_url(room_code, fingerprint) + "/complete",
		HTTPClient.METHOD_POST,
		{},
		id_token,
	)
	if not _is_current(generation):
		return _error("İşlem iptal edildi.", true)
	if not bool(complete.get("ok", false)):
		return _error(_response_error(complete, "Cloudflare uploadı tamamlanamadı."))
	progress_changed.emit(1.0, I18n.t("song_cloud_ready"), false)
	return {"ok": true, "already_ready": false}


func download_song(
		fingerprint: String,
		room_code: String,
		id_token: String,
) -> Dictionary:
	if not is_configured():
		return _error("Cloudflare Worker adresi ayarlanmamış.")
	var generation := _begin_operation()
	var song_url := _song_url(room_code, fingerprint)
	progress_changed.emit(0.0, I18n.t("song_cloud_waiting_host"), true)
	var manifest_response: Dictionary = {}
	for _attempt in range(int(ceil(
			float(MANIFEST_WAIT_SECONDS) / MANIFEST_RETRY_SECONDS))):
		manifest_response = await _request_json(
			song_url + "/manifest", HTTPClient.METHOD_GET, null, id_token)
		if not _is_current(generation):
			return _error("İşlem iptal edildi.", true)
		if bool(manifest_response.get("ok", false)):
			break
		var code := int(manifest_response.get("code", 0))
		if code != 404 and code != 409:
			return _error(_response_error(
				manifest_response, "Şarkı bilgisi Cloudflare'dan alınamadı."))
		await get_tree().create_timer(MANIFEST_RETRY_SECONDS).timeout
	if not bool(manifest_response.get("ok", false)):
		return _error("Hostun bulut yüklemesi zaman aşımına uğradı.")

	var response_data: Dictionary = manifest_response.get("data", {})
	var manifest_variant = response_data.get("manifest", {})
	if not manifest_variant is Dictionary:
		return _error("Cloudflare geçersiz şarkı bilgisi döndürdü.")
	var manifest: Dictionary = manifest_variant
	var validation := _validate_download_manifest(manifest, fingerprint)
	if not bool(validation.get("ok", false)):
		return _error(String(validation.get("error", "Geçersiz şarkı bilgisi.")))

	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	var temp_root := TEMP_DIR.path_join(
		"%s_%d" % [fingerprint.left(12), Time.get_ticks_msec()])
	if DirAccess.make_dir_recursive_absolute(temp_root) != OK:
		return _error("Şarkı için geçici klasör oluşturulamadı.")

	var total_size := int(manifest.get("total_size", 0))
	var downloaded := 0
	var files: Array = manifest.get("files", [])
	for file_index in range(files.size()):
		var file_info: Dictionary = files[file_index]
		var relative := _safe_manifest_relative(
			String(file_info.get("relative_path", "")))
		var destination := temp_root.path_join(relative)
		if DirAccess.make_dir_recursive_absolute(destination.get_base_dir()) != OK:
			return _error("İndirilen şarkının klasörü oluşturulamadı.")
		var output := FileAccess.open(destination, FileAccess.WRITE)
		if output == null:
			return _error("İndirilen şarkı dosyası kaydedilemedi.")
		var chunk_count := int(file_info.get("chunk_count", 0))
		for chunk_index in range(chunk_count):
			if not _is_current(generation):
				output.close()
				return _error("İşlem iptal edildi.", true)
			var chunk_response := await _request_bytes(
				"%s/files/%d/chunks/%d" % [
					song_url, file_index, chunk_index],
				HTTPClient.METHOD_GET,
				PackedByteArray(),
				id_token,
			)
			if not _is_current(generation):
				output.close()
				return _error("İşlem iptal edildi.", true)
			if not bool(chunk_response.get("ok", false)):
				output.close()
				return _error(_response_error(
					chunk_response, "Şarkı parçası indirilemedi."))
			var chunk: PackedByteArray = chunk_response.get(
				"body", PackedByteArray())
			var expected := mini(
				CHUNK_BYTES,
				int(file_info.get("size", 0)) - chunk_index * CHUNK_BYTES,
			)
			if chunk.size() != expected:
				output.close()
				return _error("İndirilen şarkı parçasının boyutu yanlış.")
			output.store_buffer(chunk)
			downloaded += chunk.size()
			progress_changed.emit(
				float(downloaded) / maxf(1.0, float(total_size)),
				I18n.t("song_cloud_downloading", [int(
					float(downloaded) * 100.0 / maxf(1.0, float(total_size)))]),
				true,
			)
		output.close()
		if FileAccess.get_md5(destination) \
				!= String(file_info.get("md5", "")).to_lower():
			return _error("İndirilen şarkı dosyasının doğrulaması başarısız.")

	var finalized := _finalize_download(temp_root, manifest, fingerprint)
	if not bool(finalized.get("ok", false)):
		return finalized
	progress_changed.emit(1.0, I18n.t("song_transfer_complete"), false)
	return finalized


func _build_upload_manifest(
		source_song: Dictionary, fingerprint: String) -> Dictionary:
	var source_path := String(source_song.get("path", ""))
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		return {}
	var lower := source_path.to_lower()
	var single_file := lower.ends_with(".sng") or lower.ends_with(".con") \
		or lower.ends_with(".live")
	var base_path := source_path.get_base_dir()
	var files: Array[Dictionary] = []
	if single_file:
		var entry := _manifest_file(source_path, source_path.get_file())
		if not entry.is_empty():
			files.append(entry)
	else:
		_collect_song_files(base_path, base_path, files)
	if files.is_empty() or files.size() > MAX_FILES:
		return {}
	var total_size := 0
	var entry_relative := ""
	for file in files:
		total_size += int(file.get("size", 0))
		if String(file.get("source_path", "")) == source_path:
			entry_relative = String(file.get("relative_path", ""))
	if entry_relative.is_empty() or total_size <= 0 or total_size > MAX_SONG_BYTES:
		return {}
	return {
		"name": String(source_song.get("display_name", source_path.get_file())),
		"fingerprint": fingerprint,
		"single_file": single_file,
		"entry_relative": entry_relative,
		"files": files,
		"total_size": total_size,
	}


func _manifest_file(source_path: String, relative_path: String) -> Dictionary:
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		return {}
	var size := file.get_length()
	file.close()
	var relative := _safe_manifest_relative(relative_path)
	if relative.is_empty():
		return {}
	return {
		"source_path": source_path,
		"relative_path": relative,
		"size": size,
		"md5": FileAccess.get_md5(source_path),
		"chunk_count": int(ceil(float(size) / float(CHUNK_BYTES))),
	}


func _collect_song_files(
		base_path: String,
		current_path: String,
		result: Array[Dictionary],
) -> void:
	var dir := DirAccess.open(current_path)
	if dir == null:
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			names.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for child_name in names:
		var child_path := current_path.path_join(child_name)
		if DirAccess.dir_exists_absolute(child_path):
			_collect_song_files(base_path, child_path, result)
			continue
		if child_name.ends_with(".import") or child_name.begins_with("."):
			continue
		var relative := child_path.trim_prefix(base_path).trim_prefix("/")
		var entry := _manifest_file(child_path, relative)
		if not entry.is_empty():
			result.append(entry)


func _validate_download_manifest(
		manifest: Dictionary, expected_fingerprint: String) -> Dictionary:
	if String(manifest.get("fingerprint", "")) != expected_fingerprint:
		return _error("Şarkı kimliği eşleşmiyor.", true)
	var total_size := int(manifest.get("total_size", 0))
	var files_variant = manifest.get("files", [])
	if not files_variant is Array or files_variant.is_empty() \
			or files_variant.size() > MAX_FILES \
			or total_size <= 0 or total_size > MAX_SONG_BYTES:
		return _error("Şarkı manifesti geçersiz.", true)
	var calculated_total := 0
	var entry_relative := _safe_manifest_relative(
		String(manifest.get("entry_relative", "")))
	var entry_found := false
	for file_variant in files_variant:
		if not file_variant is Dictionary:
			return _error("Şarkı dosya bilgisi geçersiz.", true)
		var file: Dictionary = file_variant
		var relative := _safe_manifest_relative(
			String(file.get("relative_path", "")))
		var size := int(file.get("size", -1))
		var md5 := String(file.get("md5", "")).to_lower()
		var chunk_count := int(file.get("chunk_count", -1))
		if relative.is_empty() or size < 0 \
				or md5.length() != 32 \
				or chunk_count != int(ceil(float(size) / float(CHUNK_BYTES))):
			return _error("Şarkı dosya bilgisi doğrulanamadı.", true)
		calculated_total += size
		entry_found = entry_found or relative == entry_relative
	if calculated_total != total_size or not entry_found:
		return _error("Şarkı toplam boyutu doğrulanamadı.", true)
	return {"ok": true}


func _finalize_download(
		temp_root: String,
		manifest: Dictionary,
		fingerprint: String,
) -> Dictionary:
	var entry_relative := _safe_manifest_relative(
		String(manifest.get("entry_relative", "")))
	var temp_entry := temp_root.path_join(entry_relative)
	if not FileAccess.file_exists(temp_entry):
		return _error("İndirilen chart bulunamadı.", true)
	if DirAccess.make_dir_recursive_absolute(USER_SONGS_DIR) != OK:
		return _error("Şarkı klasörü oluşturulamadı.", true)
	var final_entry := ""
	if bool(manifest.get("single_file", false)):
		var final_name := _safe_path_component(entry_relative.get_file())
		var desired := USER_SONGS_DIR.path_join(final_name)
		if FileAccess.file_exists(desired):
			desired = USER_SONGS_DIR.path_join(
				"%s_%s.%s" % [
					final_name.get_basename(),
					fingerprint.left(8),
					final_name.get_extension(),
				])
		if DirAccess.rename_absolute(temp_entry, desired) != OK:
			return _error("İndirilen şarkı taşınamadı.", true)
		final_entry = desired
	else:
		var folder_name := _safe_path_component(
			String(manifest.get("name", "song")).get_basename())
		var final_root := USER_SONGS_DIR.path_join(
			"%s_%s" % [folder_name, fingerprint.left(8)])
		if DirAccess.dir_exists_absolute(final_root):
			final_root += "_%d" % Time.get_ticks_msec()
		if DirAccess.rename_absolute(temp_root, final_root) != OK:
			return _error("İndirilen şarkı klasörü taşınamadı.", true)
		final_entry = final_root.path_join(entry_relative)
	return {
		"ok": true,
		"song": {
			"path": final_entry,
			"display_name": String(
				manifest.get("name", I18n.t("default_song_name"))),
		},
	}


func _request_json(
		url: String,
		method: HTTPClient.Method,
		body,
		id_token: String,
) -> Dictionary:
	var headers := PackedStringArray([
		"Authorization: Bearer %s" % id_token,
		"Content-Type: application/json",
		"Accept: application/json",
	])
	var payload := "" if body == null else JSON.stringify(body)
	return await _request(url, method, payload.to_utf8_buffer(), headers, false)


func _request_bytes(
		url: String,
		method: HTTPClient.Method,
		body: PackedByteArray,
		id_token: String,
) -> Dictionary:
	var headers := PackedStringArray([
		"Authorization: Bearer %s" % id_token,
		"Content-Type: application/octet-stream",
		"Accept: application/octet-stream, application/json",
	])
	if method == HTTPClient.METHOD_PUT:
		headers.append("Content-Length: %d" % body.size())
	return await _request(url, method, body, headers, true)


func _request(
		url: String,
		method: HTTPClient.Method,
		body: PackedByteArray,
		headers: PackedStringArray,
		raw_response: bool,
) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 45.0
	add_child(request)
	var start_error := request.request_raw(url, headers, method, body)
	if start_error != OK:
		request.queue_free()
		return {
			"ok": false,
			"code": 0,
			"error": error_string(start_error),
		}
	var response: Array = await request.request_completed
	request.queue_free()
	var result := int(response[0])
	var response_code := int(response[1])
	var response_body: PackedByteArray = response[3]
	var ok := result == HTTPRequest.RESULT_SUCCESS \
		and response_code >= 200 and response_code < 300
	if raw_response and ok:
		return {
			"ok": true,
			"code": response_code,
			"body": response_body,
		}
	var text := response_body.get_string_from_utf8()
	var data = JSON.parse_string(text) if not text.is_empty() else null
	return {
		"ok": ok,
		"code": response_code,
		"data": data,
		"error": "" if ok else text,
	}


func _response_error(response: Dictionary, fallback: String) -> String:
	var data = response.get("data")
	if data is Dictionary:
		var message := String(data.get("error", "")).strip_edges()
		if not message.is_empty():
			return message
	var raw := String(response.get("error", "")).strip_edges()
	return raw.left(240) if not raw.is_empty() else fallback


func _song_url(room_code: String, fingerprint: String) -> String:
	return "%s/v1/rooms/%s/songs/%s" % [
		_base_url,
		room_code.to_upper(),
		fingerprint.to_lower(),
	]


func _begin_operation() -> int:
	_operation_generation += 1
	return _operation_generation


func _is_current(generation: int) -> bool:
	return generation == _operation_generation


func _error(message: String, silent: bool = false) -> Dictionary:
	if not silent:
		push_warning("Cloud song transfer failed: %s" % message)
	var public_message := I18n.t("song_transfer_error_reason")
	if not silent:
		progress_changed.emit(0.0, public_message, false)
	return {"ok": false, "error": public_message, "cancelled": silent}


func _safe_manifest_relative(value: String) -> String:
	var normalized := value.replace("\\", "/").trim_prefix("/")
	var safe_parts: Array[String] = []
	for part in normalized.split("/", false):
		if part == "." or part == "..":
			return ""
		var safe := _safe_path_component(part)
		if safe.is_empty():
			return ""
		safe_parts.append(safe)
	return "/".join(safe_parts)


func _safe_path_component(value: String) -> String:
	var result := ""
	for character in value:
		if character in '<>:"/\\|?*' or character.unicode_at(0) < 32:
			result += "_"
		else:
			result += character
	result = result.strip_edges().trim_suffix(".")
	return result.left(96) if not result.is_empty() else "song"
