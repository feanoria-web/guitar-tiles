extends SceneTree

const CloudSongTransferScript = preload("res://scripts/cloud_song_transfer.gd")


func _initialize() -> void:
	var root_dir := "user://cloud-transfer-test"
	DirAccess.make_dir_recursive_absolute(root_dir)
	var chart_path := root_dir.path_join("notes.chart")
	var audio_path := root_dir.path_join("song.ogg")
	_write(chart_path, "[Song]\n{\n  Name = \"Relay Test\"\n}\n")
	_write(audio_path, "fake-audio-payload")

	var transfer = CloudSongTransferScript.new()
	root.add_child(transfer)
	var fingerprint := "0123456789abcdef0123456789abcdef"
	var manifest: Dictionary = transfer._build_upload_manifest({
		"path": chart_path,
		"display_name": "Relay Test",
	}, fingerprint)
	_check(not manifest.is_empty(), "Cloud manifest should be generated")
	_check(int(manifest.get("total_size", 0)) > 0,
		"Cloud manifest should include a positive total size")
	_check(Array(manifest.get("files", [])).size() == 2,
		"Cloud manifest should include chart and audio")

	var public_manifest := manifest.duplicate(true)
	for file in public_manifest.get("files", []):
		file.erase("source_path")
	var validation: Dictionary = transfer._validate_download_manifest(
		public_manifest, fingerprint)
	_check(bool(validation.get("ok", false)),
		"Generated cloud manifest should pass download validation")
	_check(transfer._safe_manifest_relative("../secret").is_empty(),
		"Cloud paths must reject parent traversal")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(chart_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(audio_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root_dir))
	print("Cloud song transfer rules: PASS")
	quit(0)


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "Test file should be writable")
	file.store_string(content)
	file.close()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
