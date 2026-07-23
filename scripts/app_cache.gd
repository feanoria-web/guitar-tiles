extends Node

# A stable 60 Hz render budget is a better default for Android than chasing
# high-refresh displays until the GPU gets hot and oscillates between 60/90 Hz.
# Gameplay timing is audio-clock based, so this does not change note accuracy.
const ANDROID_TARGET_FPS := 60

# Session cache shared by the menu and gameplay scenes. It intentionally lives
# in an autoload so changing scenes does not discard expensive song metadata.
var song_list_valid: bool = false
var songs: Array = []
var album_art: Dictionary = {}       # song path -> cached thumbnail path (or "")
var instrument_data: Dictionary = {} # song path -> scanned instruments

func _ready() -> void:
	if OS.has_feature("android"):
		Engine.max_fps = ANDROID_TARGET_FPS

func store_songs(value: Array) -> void:
	songs = value.duplicate(true)
	song_list_valid = true

func invalidate_song_list() -> void:
	song_list_valid = false
	songs.clear()

func remove_song(path: String) -> void:
	album_art.erase(path)
	instrument_data.erase(path)
	invalidate_song_list()
