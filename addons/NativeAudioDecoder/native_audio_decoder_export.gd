@tool
extends EditorPlugin

var _export_plugin: AndroidExportPlugin

func _enter_tree() -> void:
	_export_plugin = AndroidExportPlugin.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null

class AndroidExportPlugin extends EditorExportPlugin:
	var _plugin_name := "NativeAudioDecoder"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		if platform is EditorExportPlatformAndroid:
			return true
		return false

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray([_plugin_name + "/NativeAudioDecoder-release.aar"])

	func _get_name() -> String:
		return _plugin_name
