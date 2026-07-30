extends Node

## Persistent 2-4 player multiplayer session.
## Firebase Realtime Database is used only for rooms/WebRTC signalling.
## Once connected, gameplay messages travel over reliable WebRTC data channels.

signal state_changed(state: String, detail: String)
signal lobby_changed(players: Array, room: Dictionary)
signal scoreboard_changed(snapshot: Dictionary)
signal match_prepare_requested(config: Dictionary)
signal match_start_scheduled(local_tick_msec: int)
signal band_failed
signal session_error(message: String)
signal song_transfer_progress_changed(progress: float, detail: String, active: bool)
signal song_transfer_completed(song: Dictionary)

const GameScript = preload("res://scripts/game.gd")
const PlayabilityScript = preload("res://scripts/playability.gd")
const CloudSongTransferScript = preload("res://scripts/cloud_song_transfer.gd")
const CONFIG_PATH := "res://multiplayer_config.json"
const MAX_PLAYERS := 4
const MIN_PLAYERS := 2
const POLL_INTERVAL := 0.75
const CONNECTION_POLL_INTERVAL := 1.0 / 30.0
const PLAYER_STATE_INTERVAL := 0.10
const SNAPSHOT_INTERVAL := 0.20
const CHANNEL_ID := 7
const REALTIME_CHANNEL_ID := 8
const TRANSFER_CHANNEL_ID := 9
const REALTIME_PACKET_TYPES := ["GAME_STATE", "SNAPSHOT"]
const MAX_CONTROL_PACKETS_PER_POLL := 4
const MAX_REALTIME_PACKETS_PER_POLL := 16
const MAX_TRANSFER_PACKETS_PER_POLL := 2
const SONG_TRANSFER_CHUNK_SIZE := 32 * 1024
const SONG_TRANSFER_BUFFER_LIMIT := 128 * 1024
const SONG_TRANSFER_ACK_WINDOW_BYTES := 128 * 1024
const MAX_SONG_TRANSFER_BYTES := 512 * 1024 * 1024
const SONG_TRANSFER_STALL_TIMEOUT_MSEC := 45_000
const SONG_TRANSFER_RETRY_INTERVAL_MSEC := 750
const SONG_REQUEST_RETRY_INTERVAL_MSEC := 2_000
const MATCH_HANDSHAKE_INTERVAL_MSEC := 750
const USER_SONGS_DIR := "user://songs"
const SONG_TRANSFER_TEMP_DIR := "user://multiplayer_downloads"

var configured: bool = false
var session_state: String = "idle"
var room_code: String = ""
var room_mode: String = "battle"
var is_host: bool = false
var local_uid: String = ""
var local_name: String = ""
var players: Dictionary = {}
var room_data: Dictionary = {}
var song_catalog: Array = []
var selected_song: Dictionary = {}
var match_active: bool = false
var match_loading: bool = false
var start_local_tick_msec: int = 0
var latest_snapshot: Dictionary = {}
var song_transfer_active: bool = false
var song_transfer_progress: float = 0.0
var song_transfer_detail: String = ""

var _database_url: String = ""
var _api_key: String = ""
var _song_cloud_url: String = ""
var _ice_servers: Array = []
var _id_token: String = ""
var _cloud_transfer: Node = null
var _cloud_upload_fingerprint := ""
var _cloud_download_fingerprint := ""
var _cloud_download_active := false
var _cloud_failed_fingerprints: Dictionary = {}
var _poll_elapsed := 0.0
var _connection_poll_elapsed := 0.0
var _player_state_elapsed := 0.0
var _snapshot_elapsed := 0.0
var _poll_busy := false
var _sequence := 0
var _connections: Dictionary = {}
var _seen_remote_ice: Dictionary = {}
var _last_room_status := ""
var _clock_offset_msec := 0.0
var _best_clock_rtt := INF
var _host_scores: Dictionary = {}
var _loaded_players: Dictionary = {}
var _finished_players: Dictionary = {}
var _pending_local_state: Dictionary = {}
var _band_failed := false
var _requested_song_fingerprint := ""
var _song_request_tick_msec := 0
var _song_send_transfers: Dictionary = {}
var _song_send_queue: Array[String] = []
var _active_song_send_uid := ""
var _song_receive_transfer: Dictionary = {}
var _last_completed_transfer_id := ""
var _last_completed_transfer_host_uid := ""
var _match_id := ""
var _match_config: Dictionary = {}
var _match_participant_uids: Array[String] = []
var _prepare_acked: Dictionary = {}
var _start_acked: Dictionary = {}
var _match_start_packet: Dictionary = {}
var _last_match_handshake_tick := 0
var _local_game_loaded := false
var _match_entry_started := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cloud_transfer = CloudSongTransferScript.new()
	add_child(_cloud_transfer)
	_cloud_transfer.progress_changed.connect(_on_cloud_transfer_progress)
	_load_config()

func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	_database_url = String(parsed.get("firebase_database_url", "")).strip_edges().trim_suffix("/")
	_api_key = String(parsed.get("firebase_api_key", "")).strip_edges()
	_song_cloud_url = String(parsed.get("song_cloud_url", "")).strip_edges().trim_suffix("/")
	_cloud_transfer.configure(_song_cloud_url)
	_ice_servers = parsed.get("ice_servers", [])
	if _ice_servers.is_empty():
		_ice_servers = [
			{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]}
		]
	configured = not _database_url.is_empty() and not _api_key.is_empty()

func set_song_catalog(catalog: Array) -> void:
	song_catalog = catalog.duplicate(true)

func create_room(mode: String, player_name: String) -> void:
	if not configured:
		_fail(I18n.t("mp_firebase_missing"))
		return
	_reset_session()
	room_mode = "band" if mode == "band" else "battle"
	local_name = _clean_name(player_name)
	is_host = true
	_set_state("connecting", I18n.t("mp_connecting"))
	if not await _ensure_auth():
		return
	var found_free_code := false
	for _attempt in range(8):
		room_code = _generate_room_code()
		var existing := await _firebase("GET", "rooms/%s" % room_code)
		if existing.get("ok", false) and existing.get("data") == null:
			found_free_code = true
			break
	if not found_free_code:
		room_code = ""
		_fail(I18n.t("mp_room_code_failed"))
		return
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	var player := _new_player(local_uid, local_name, true)
	var initial := {
		"meta": {
			"host_uid": local_uid,
			"mode": room_mode,
			"status": "lobby",
			"created_at": now,
			"max_players": MAX_PLAYERS,
			"version": 1,
		},
		"players": {local_uid: player},
	}
	var result := await _firebase("PUT", "rooms/%s" % room_code, initial)
	if not result.get("ok", false):
		_fail(I18n.t("mp_room_create_failed", [
			result.get("error", I18n.t("mp_firebase_error"))]))
		return
	players = {local_uid: player}
	room_data = initial
	_set_state("lobby", I18n.t("mp_room_ready", [room_code]))
	lobby_changed.emit(_players_array(), room_data)

func join_room(code: String, player_name: String) -> void:
	if not configured:
		_fail(I18n.t("mp_firebase_missing"))
		return
	var requested_code := _clean_code(code)
	if session_state == "lobby":
		if is_host and requested_code == room_code:
			_fail(I18n.t("mp_own_room"), false)
		else:
			_fail(I18n.t("mp_leave_first"), false)
		return
	_reset_session()
	room_code = requested_code
	local_name = _clean_name(player_name)
	is_host = false
	if room_code.length() < 4:
		_fail(I18n.t("mp_valid_code"))
		return
	_set_state("connecting", I18n.t("mp_searching_room"))
	if not await _ensure_auth():
		return
	var result := await _firebase("GET", "rooms/%s" % room_code)
	if not result.get("ok", false) or not result.get("data") is Dictionary:
		_fail(I18n.t("mp_room_not_found"))
		return
	var found: Dictionary = result["data"]
	var meta: Dictionary = found.get("meta", {})
	var found_players: Dictionary = found.get("players", {})
	if String(meta.get("host_uid", "")) == local_uid:
		_fail(I18n.t("mp_own_room"))
		return
	if String(meta.get("status", "")) != "lobby":
		_fail(I18n.t("mp_room_closed"))
		return
	if found_players.size() >= MAX_PLAYERS:
		_fail(I18n.t("mp_room_full"))
		return
	room_mode = String(meta.get("mode", "battle"))
	var player := _new_player(local_uid, local_name, false)
	var put_result := await _firebase(
		"PUT", "rooms/%s/players/%s" % [room_code, local_uid], player)
	if not put_result.get("ok", false):
		_fail(I18n.t("mp_join_failed"))
		return
	players = found_players
	players[local_uid] = player
	room_data = found
	_set_state("lobby", I18n.t("mp_joined_room", [room_code]))
	lobby_changed.emit(_players_array(), room_data)
	_ensure_guest_connection()

func leave_room() -> void:
	if not room_code.is_empty() and not _id_token.is_empty():
		if is_host:
			_firebase("DELETE", "rooms/%s" % room_code)
		else:
			_firebase("DELETE", "rooms/%s/players/%s" % [room_code, local_uid])
	_close_connections()
	_reset_session()
	_set_state("idle", "")

func update_local_player(patch: Dictionary) -> void:
	if session_state != "lobby" or local_uid.is_empty() \
			or match_loading or match_active:
		return
	var current: Dictionary = players.get(local_uid, _new_player(local_uid, local_name, is_host))
	for key in patch:
		current[key] = patch[key]
	if room_mode == "band" and String(current.get("instrument", "")).is_empty():
		current["ready"] = false
	players[local_uid] = current
	_firebase("PATCH", "rooms/%s/players/%s" % [room_code, local_uid], patch)
	lobby_changed.emit(_players_array(), room_data)
	if _has_open_channel():
		_send_packet({"type": "PLAYER_UPDATE", "player": current})

func host_select_song(song: Dictionary, instruments: Dictionary) -> void:
	if not is_host or session_state != "lobby" \
			or match_loading or match_active:
		return
	_reset_song_transfers()
	var descriptor := {
		"name": String(song.get(
			"display_name", song.get("path", I18n.t("default_song_name")))),
		"fingerprint": song_fingerprint(String(song.get("path", ""))),
		"instruments": instruments,
		"preset": String(selected_song.get("preset", "Tiles")),
		"mode": String(selected_song.get("mode", "guitar")),
	}
	selected_song = descriptor
	room_data["song"] = descriptor
	for uid in players:
		players[uid]["ready"] = false
		players[uid]["song_ok"] = uid == local_uid
		var instrument := String(players[uid].get("instrument", ""))
		if not instruments.has(instrument):
			players[uid]["instrument"] = ""
			players[uid]["difficulty"] = "Expert"
	_firebase("PUT", "rooms/%s/song" % room_code, descriptor)
	_send_packet({"type": "LOBBY", "song": descriptor, "players": _players_array()})
	_update_local_song_match()
	_begin_cloud_song_upload(song, String(descriptor.get("fingerprint", "")))
	lobby_changed.emit(_players_array(), room_data)

func host_update_match_options(mode: String, preset: String) -> void:
	if not is_host or session_state != "lobby" or selected_song.is_empty() \
			or match_loading or match_active:
		return
	selected_song["mode"] = "piano" if mode == "piano" else "guitar"
	selected_song["preset"] = preset if preset in PlayabilityScript.PRESET_ORDER else "Tiles"
	room_data["song"] = selected_song
	for uid in players:
		players[uid]["ready"] = false
	_firebase("PATCH", "rooms/%s" % room_code, {
		"song": selected_song,
		"players": players,
	})
	_send_packet({
		"type": "LOBBY",
		"song": selected_song,
		"players": _players_array(),
	})
	lobby_changed.emit(_players_array(), room_data)

func can_start_match() -> Dictionary:
	var list := _players_array()
	if not is_host:
		return {"ok": false, "message": I18n.t("mp_only_host_start")}
	if match_loading or match_active:
		return {"ok": false, "message": I18n.t("mp_match_starting")}
	if list.size() < MIN_PLAYERS or list.size() > MAX_PLAYERS:
		return {"ok": false, "message": I18n.t("mp_player_count")}
	if selected_song.is_empty():
		return {"ok": false, "message": I18n.t("mp_choose_song_first")}
	var roles: Dictionary = {}
	for player in list:
		if not bool(player.get("ready", false)):
			return {"ok": false, "message": I18n.t("mp_player_not_ready", [
				player.get("name", I18n.t("default_player_name"))])}
		if not bool(player.get("song_ok", false)):
			return {"ok": false, "message": I18n.t("mp_player_missing_song", [
				player.get("name", I18n.t("default_player_name"))])}
		var instrument := String(player.get("instrument", ""))
		if instrument.is_empty():
			return {"ok": false, "message": I18n.t("mp_player_no_instrument", [
				player.get("name", I18n.t("default_player_name"))])}
		if room_mode == "band":
			if roles.has(instrument):
				return {"ok": false, "message": I18n.t("mp_unique_band_roles")}
			roles[instrument] = true
		var uid := String(player.get("uid", ""))
		if uid != local_uid:
			var connection: Dictionary = _connections.get(uid, {})
			if not bool(connection.get("open", false)):
				return {
					"ok": false,
					"message": I18n.t("mp_connection_not_ready", [player.get(
						"name", I18n.t("default_player_name"))]),
				}
	return {"ok": true, "message": ""}

func host_start_match() -> void:
	var check := can_start_match()
	if not check.get("ok", false):
		_fail(String(check.get(
			"message", I18n.t("mp_start_failed"))), false)
		return
	var config := {
		"mode": room_mode,
		"song": selected_song,
		"players": _players_array(),
	}
	_match_id = "%s-%d" % [local_uid.left(8), Time.get_ticks_msec()]
	config["match_id"] = _match_id
	_match_config = config.duplicate(true)
	_match_participant_uids.clear()
	for participant in config["players"]:
		if participant is Dictionary:
			_match_participant_uids.append(String(participant.get("uid", "")))
	match_loading = true
	_loaded_players.clear()
	_prepare_acked.clear()
	_prepare_acked[local_uid] = true
	_start_acked.clear()
	_match_start_packet.clear()
	_local_game_loaded = false
	_match_entry_started = false
	_last_match_handshake_tick = 0
	_host_scores.clear()
	_firebase("PATCH", "rooms/%s/meta" % room_code, {"status": "loading"})
	_send_prepare_to_missing()
	_maybe_enter_match()

func notify_game_loaded() -> void:
	if not match_loading:
		return
	_local_game_loaded = true
	if is_host:
		_loaded_players[local_uid] = true
		_maybe_schedule_start()
	else:
		_send_packet({
			"type": "LOADED",
			"uid": local_uid,
			"match_id": _match_id,
		})

func submit_gameplay_state(state: Dictionary) -> void:
	if not match_active:
		return
	_sequence += 1
	_pending_local_state = {
		"uid": local_uid,
		"seq": _sequence,
		"score": maxi(0, int(state.get("score", 0))),
		"combo": maxi(0, int(state.get("combo", 0))),
		"health": clampf(float(state.get("health", 0.5)), 0.0, 1.0),
		"song_ms": maxi(0, int(state.get("song_ms", 0))),
		"finished": bool(state.get("finished", false)),
	}

func notify_game_finished(state: Dictionary) -> void:
	state["finished"] = true
	submit_gameplay_state(state)
	if is_host:
		_finished_players[local_uid] = true
	else:
		_send_packet({"type": "FINISH", "state": _pending_local_state})

func get_start_seconds() -> float:
	if start_local_tick_msec <= 0:
		return -1.0
	return float(start_local_tick_msec - Time.get_ticks_msec()) / 1000.0

func get_scoreboard_text() -> String:
	var rows: Array = latest_snapshot.get("players", [])
	if rows.is_empty():
		return ""
	rows = rows.duplicate(true)
	rows.sort_custom(func(a, b): return int(a.get("score", 0)) > int(b.get("score", 0)))
	var lines: Array[String] = []
	if room_mode == "band":
		lines.append(I18n.t("scoreboard_band_line", [
			int(latest_snapshot.get("total_score", 0)),
			int(float(latest_snapshot.get("band_health", 0.0)) * 100.0)]))
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var prefix := "%d." % (i + 1) if room_mode == "battle" else "•"
		lines.append("%s %s  %d  x%d" % [
			prefix, row.get("name", I18n.t("default_player_name")),
			int(row.get("score", 0)), int(row.get("combo", 0))])
	return "\n".join(lines)

func find_local_song(fingerprint: String) -> Dictionary:
	for song in song_catalog:
		if song_fingerprint(String(song.get("path", ""))) == fingerprint:
			return song
	return {}

func song_fingerprint(path: String) -> String:
	if path.is_empty():
		return ""
	var pieces: Array[String] = []
	if FileAccess.file_exists(path):
		pieces.append(FileAccess.get_md5(path))
		var lower := path.to_lower()
		if lower.ends_with(".sng") or lower.ends_with(".con") or lower.ends_with(".live"):
			return "|".join(pieces).md5_text()
		var parent := path.get_base_dir()
		var dir := DirAccess.open(parent)
		if dir:
			var names: Array[String] = []
			dir.list_dir_begin()
			var name := dir.get_next()
			while not name.is_empty():
				if not dir.current_is_dir() and _is_audio_file(name):
					names.append(name)
				name = dir.get_next()
			dir.list_dir_end()
			names.sort()
			for audio_name in names:
				pieces.append(audio_name.to_lower())
				pieces.append(FileAccess.get_md5(parent.path_join(audio_name)))
	return "|".join(pieces).md5_text()

func _process(delta: float) -> void:
	_check_song_transfer_timeout()
	_connection_poll_elapsed += delta
	if _connection_poll_elapsed >= CONNECTION_POLL_INTERVAL:
		_connection_poll_elapsed = fmod(
			_connection_poll_elapsed, CONNECTION_POLL_INTERVAL)
		_poll_connections()
		_pump_song_transfers()
		_pump_song_receive_ack()
		_pump_match_handshake()
	# Firebase is only signaling/lobby transport. Once gameplay starts, WebRTC
	# owns all live traffic. Continuing the full-room GET every 750 ms caused
	# repeatable 200 ms Android frame stalls while parsing the room response.
	if not match_active and (session_state == "lobby" or match_loading):
		_poll_elapsed += delta
		if _poll_elapsed >= POLL_INTERVAL and not _poll_busy:
			_poll_elapsed = 0.0
			_poll_room()
	if not match_active:
		return
	if not _pending_local_state.is_empty():
		_player_state_elapsed += delta
		if _player_state_elapsed >= PLAYER_STATE_INTERVAL:
			_player_state_elapsed = fmod(_player_state_elapsed, PLAYER_STATE_INTERVAL)
			if is_host:
				_accept_game_state(_pending_local_state)
			else:
				_send_packet({"type": "GAME_STATE", "state": _pending_local_state})
	if is_host:
		_snapshot_elapsed += delta
		if _snapshot_elapsed >= SNAPSHOT_INTERVAL:
			_snapshot_elapsed = fmod(_snapshot_elapsed, SNAPSHOT_INTERVAL)
			_broadcast_snapshot()

func _poll_room() -> void:
	if room_code.is_empty():
		return
	_poll_busy = true
	var result := await _firebase("GET", "rooms/%s" % room_code)
	_poll_busy = false
	if not result.get("ok", false) or not result.get("data") is Dictionary:
		return
	room_data = result["data"]
	var meta: Dictionary = room_data.get("meta", {})
	var status := String(meta.get("status", ""))
	if not _last_room_status.is_empty() and status == "closed":
		_fail(I18n.t("mp_host_closed"))
		return
	_last_room_status = status
	var remote_players = room_data.get("players", {})
	if remote_players is Dictionary:
		# The local player owns these fields. A Firebase poll may complete just
		# before the preceding PATCH and return stale values; never let that
		# temporary response visually reset instrument/ready selections.
		var local_before: Dictionary = players.get(local_uid, {}).duplicate(true)
		players = remote_players
		if not local_before.is_empty() and players.has(local_uid):
			var remote_local: Dictionary = players[local_uid]
			for field in [
				"name", "ready", "song_ok", "instrument", "difficulty",
				"game_mode", "preset"
			]:
				if local_before.has(field):
					remote_local[field] = local_before[field]
			players[local_uid] = remote_local
	if room_data.get("song") is Dictionary:
		selected_song = room_data["song"]
		_update_local_song_match()
	if is_host:
		for transfer_uid in _song_send_transfers.keys():
			if bool(players.get(transfer_uid, {}).get("song_ok", false)):
				_complete_song_send(String(transfer_uid))
		for uid in players:
			if uid != local_uid:
				_ensure_host_connection(String(uid))
	else:
		_ensure_guest_connection()
	_apply_remote_signalling()
	lobby_changed.emit(_players_array(), room_data)

func _update_local_song_match() -> void:
	if selected_song.is_empty() or not players.has(local_uid):
		return
	var fingerprint := String(selected_song.get("fingerprint", ""))
	if _cloud_download_active and _cloud_download_fingerprint != fingerprint:
		_cloud_transfer.cancel()
		_cloud_download_active = false
		_cloud_download_fingerprint = ""
	if not _song_receive_transfer.is_empty() \
			and String(_song_receive_transfer.get("fingerprint", "")) != fingerprint:
		_close_received_file()
		_song_receive_transfer.clear()
		_requested_song_fingerprint = ""
		_set_song_transfer_state(false, 0.0, "")
	var local_song := find_local_song(fingerprint)
	var ok := not local_song.is_empty()
	if bool(players[local_uid].get("song_ok", false)) != ok:
		update_local_player({"song_ok": ok, "ready": false})
	if ok:
		if not is_host and _cloud_download_active:
			_cloud_transfer.cancel()
			_cloud_download_active = false
			_cloud_download_fingerprint = ""
		_requested_song_fingerprint = ""
		return
	if not is_host and not fingerprint.is_empty() \
			and _requested_song_fingerprint != fingerprint:
		_requested_song_fingerprint = fingerprint
		_song_request_tick_msec = Time.get_ticks_msec()
		if _cloud_transfer.is_configured() \
				and not _cloud_failed_fingerprints.has(fingerprint):
			_begin_cloud_song_download(fingerprint)
			return
		_set_song_transfer_state(
			true, 0.0,
			I18n.t("song_transfer_requesting", [
				selected_song.get("name", I18n.t("default_song_name"))]))
		_send_packet({
			"type": "SONG_REQUEST",
			"fingerprint": fingerprint,
		})

func _begin_cloud_song_upload(source_song: Dictionary, fingerprint: String) -> void:
	if not is_host or fingerprint.is_empty() \
			or not _cloud_transfer.is_configured():
		return
	_cloud_upload_fingerprint = fingerprint
	_cloud_failed_fingerprints.erase(fingerprint)
	_run_cloud_song_upload(source_song, fingerprint)

func _run_cloud_song_upload(
		source_song: Dictionary, fingerprint: String) -> void:
	var result: Dictionary = await _cloud_transfer.upload_song(
		source_song, fingerprint, room_code, _id_token)
	if fingerprint != _cloud_upload_fingerprint \
			or fingerprint != String(selected_song.get("fingerprint", "")):
		return
	_cloud_upload_fingerprint = ""
	if bool(result.get("ok", false)):
		_set_song_transfer_state(false, 1.0, I18n.t("song_cloud_ready"))
		_send_packet({
			"type": "SONG_CLOUD_READY",
			"fingerprint": fingerprint,
		})
		return
	if bool(result.get("cancelled", false)):
		return
	_cloud_failed_fingerprints[fingerprint] = true
	_set_song_transfer_state(
		false, 0.0,
		I18n.t("song_cloud_fallback"))

func _begin_cloud_song_download(fingerprint: String) -> void:
	if is_host or _cloud_download_active or fingerprint.is_empty():
		return
	_cloud_download_active = true
	_cloud_download_fingerprint = fingerprint
	_run_cloud_song_download(fingerprint)

func _run_cloud_song_download(fingerprint: String) -> void:
	var result: Dictionary = await _cloud_transfer.download_song(
		fingerprint, room_code, _id_token)
	if fingerprint != _cloud_download_fingerprint:
		return
	_cloud_download_active = false
	_cloud_download_fingerprint = ""
	if bool(result.get("ok", false)):
		var downloaded_song: Dictionary = result.get("song", {})
		var final_entry := String(downloaded_song.get("path", ""))
		if not final_entry.is_empty() \
				and song_fingerprint(final_entry) == fingerprint:
			song_catalog.append(downloaded_song)
			_requested_song_fingerprint = ""
			update_local_player({"song_ok": true, "ready": false})
			_set_song_transfer_state(false, 1.0, I18n.t("song_transfer_complete"))
			song_transfer_completed.emit(downloaded_song)
			lobby_changed.emit(_players_array(), room_data)
			return
		result = {
			"ok": false,
			"error": I18n.t("song_transfer_error_reason"),
		}
	if bool(result.get("cancelled", false)):
		return
	_cloud_failed_fingerprints[fingerprint] = true
	_requested_song_fingerprint = fingerprint
	_song_request_tick_msec = Time.get_ticks_msec()
	_set_song_transfer_state(
		true, 0.0,
		I18n.t("song_webrtc_fallback"))
	_send_packet({
		"type": "SONG_REQUEST",
		"fingerprint": fingerprint,
	})

func _on_cloud_transfer_progress(
		progress: float, detail: String, active: bool) -> void:
	_set_song_transfer_state(active, progress, detail)

func _ensure_host_connection(uid: String) -> void:
	if _connections.has(uid):
		return
	var connection := _new_connection(uid)
	if connection.is_empty():
		return
	_connections[uid] = connection
	var peer: WebRTCPeerConnection = connection["peer"]
	peer.create_offer()

func _ensure_guest_connection() -> void:
	var host_uid := String(room_data.get("meta", {}).get("host_uid", ""))
	if host_uid.is_empty() or _connections.has(host_uid):
		return
	var connection := _new_connection(host_uid)
	if not connection.is_empty():
		_connections[host_uid] = connection

func _new_connection(uid: String) -> Dictionary:
	var peer := WebRTCPeerConnection.new()
	var err := peer.initialize({"iceServers": _ice_servers})
	if err != OK:
		_fail(I18n.t("mp_webrtc_failed"))
		return {}
	peer.session_description_created.connect(_on_session_description.bind(uid))
	peer.ice_candidate_created.connect(_on_ice_candidate.bind(uid))
	var channel := peer.create_data_channel("riffline", {
		"id": CHANNEL_ID, "negotiated": true, "ordered": true})
	if channel == null:
		_fail(I18n.t("mp_webrtc_failed"))
		return {}
	var realtime_channel := peer.create_data_channel("riffline-realtime", {
		"id": REALTIME_CHANNEL_ID,
		"negotiated": true,
		"ordered": false,
		"maxRetransmits": 0,
	})
	if realtime_channel == null:
		# Keep multiplayer functional on unusual WebRTC implementations; live
		# packets fall back to the reliable control channel.
		realtime_channel = channel
	var transfer_channel := peer.create_data_channel("riffline-song-transfer", {
		"id": TRANSFER_CHANNEL_ID,
		"negotiated": true,
		"ordered": true,
	})
	return {
		"peer": peer,
		"channel": channel,
		"realtime_channel": realtime_channel,
		"transfer_channel": transfer_channel,
		"open": false,
	}

func _on_session_description(type: String, sdp: String, uid: String) -> void:
	if not _connections.has(uid):
		return
	var peer: WebRTCPeerConnection = _connections[uid]["peer"]
	peer.set_local_description(type, sdp)
	if is_host:
		_firebase("PUT", "rooms/%s/offers/%s" % [room_code, uid],
			{"type": type, "sdp": sdp})
	else:
		_firebase("PUT", "rooms/%s/answers/%s" % [room_code, local_uid],
			{"type": type, "sdp": sdp})

func _on_ice_candidate(media: String, index: int, candidate: String, uid: String) -> void:
	var side := "host" if is_host else "guest"
	var target := uid if is_host else local_uid
	var key := "%d_%d" % [Time.get_ticks_msec(), randi_range(100, 999)]
	_firebase("PUT", "rooms/%s/ice/%s/%s/%s" % [room_code, side, target, key], {
		"media": media, "index": index, "candidate": candidate})

func _apply_remote_signalling() -> void:
	if is_host:
		var answers: Dictionary = room_data.get("answers", {})
		for uid in answers:
			if _connections.has(uid):
				var answer: Dictionary = answers[uid]
				var marker := "answer_%s" % uid
				if not _seen_remote_ice.has(marker):
					_seen_remote_ice[marker] = true
					var peer: WebRTCPeerConnection = _connections[uid]["peer"]
					peer.set_remote_description(
						String(answer.get("type", "answer")), String(answer.get("sdp", "")))
	else:
		var offer: Dictionary = room_data.get("offers", {}).get(local_uid, {})
		var host_uid := String(room_data.get("meta", {}).get("host_uid", ""))
		if not offer.is_empty() and _connections.has(host_uid) and not _seen_remote_ice.has("offer"):
			_seen_remote_ice["offer"] = true
			var peer: WebRTCPeerConnection = _connections[host_uid]["peer"]
			peer.set_remote_description(
				String(offer.get("type", "offer")), String(offer.get("sdp", "")))
			peer.create_answer()
	var remote_side := "guest" if is_host else "host"
	var ice_by_user: Dictionary = room_data.get("ice", {}).get(remote_side, {})
	if is_host:
		for uid in ice_by_user:
			_apply_ice_for(String(uid), ice_by_user[uid])
	else:
		_apply_ice_for(
			String(room_data.get("meta", {}).get("host_uid", "")),
			ice_by_user.get(local_uid, {}))

func _apply_ice_for(uid: String, candidates) -> void:
	if not candidates is Dictionary or not _connections.has(uid):
		return
	var peer: WebRTCPeerConnection = _connections[uid]["peer"]
	for key in candidates:
		var marker := "ice_%s_%s" % [uid, key]
		if _seen_remote_ice.has(marker):
			continue
		_seen_remote_ice[marker] = true
		var item: Dictionary = candidates[key]
		peer.add_ice_candidate(
			String(item.get("media", "")),
			int(item.get("index", 0)),
			String(item.get("candidate", "")))

func _poll_connections() -> void:
	for uid in _connections.keys():
		var connection: Dictionary = _connections[uid]
		var peer: WebRTCPeerConnection = connection["peer"]
		var channel: WebRTCDataChannel = connection["channel"]
		var realtime_channel: WebRTCDataChannel = connection.get(
			"realtime_channel", channel)
		var transfer_channel: WebRTCDataChannel = connection.get(
			"transfer_channel", null)
		peer.poll()
		if channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			if not bool(connection.get("open", false)):
				connection["open"] = true
				_connections[uid] = connection
				_on_channel_open(String(uid))
			_drain_channel(channel, String(uid), false)
		elif bool(connection.get("open", false)):
			connection["open"] = false
			_connections[uid] = connection
		if realtime_channel != channel \
				and realtime_channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			_drain_channel(realtime_channel, String(uid), true)
		if transfer_channel != null \
				and transfer_channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			_drain_transfer_channel(transfer_channel, String(uid))

func _drain_channel(channel: WebRTCDataChannel, uid: String, realtime: bool) -> void:
	if realtime:
		# Realtime state replaces older state. Drain a bounded batch and decode
		# only its newest packet so a network burst can never monopolize a frame.
		var newest := PackedByteArray()
		var packet_count := mini(
			channel.get_available_packet_count(), MAX_REALTIME_PACKETS_PER_POLL)
		for _packet_index in range(packet_count):
			newest = channel.get_packet()
		if not newest.is_empty():
			var packet = _decode_realtime_packet(newest)
			if packet is Dictionary:
				_receive_packet(packet, uid)
		return
	var packet_count := mini(
		channel.get_available_packet_count(), MAX_CONTROL_PACKETS_PER_POLL)
	for _packet_index in range(packet_count):
		var packet = JSON.parse_string(channel.get_packet().get_string_from_utf8())
		if packet is Dictionary:
			_receive_packet(packet, uid)

func _decode_realtime_packet(data: PackedByteArray) -> Variant:
	# v0.3.4 briefly sent Variant-encoded realtime packets, while earlier
	# versions use JSON. Detect the format before decoding so mixed-version
	# rooms never call bytes_to_var() on JSON and spam the main thread.
	if data.size() >= 4 and data.decode_u32(0) == TYPE_DICTIONARY:
		return bytes_to_var(data)
	return JSON.parse_string(data.get_string_from_utf8())

func _drain_transfer_channel(channel: WebRTCDataChannel, uid: String) -> void:
	var packet_count := mini(
		channel.get_available_packet_count(), MAX_TRANSFER_PACKETS_PER_POLL)
	for _packet_index in range(packet_count):
		var bytes := channel.get_packet()
		if bytes.size() < 4 or bytes.decode_u32(0) != TYPE_DICTIONARY:
			continue
		var packet = bytes_to_var(bytes)
		if packet is Dictionary:
			_receive_transfer_packet(packet, uid)

func _receive_transfer_packet(packet: Dictionary, from_uid: String) -> void:
	var type := String(packet.get("type", ""))
	match type:
		"SONG_OFFER":
			if not is_host:
				_begin_song_receive(packet, from_uid)
		"SONG_FILE_START":
			if not is_host:
				_begin_received_file(packet, from_uid)
		"SONG_CHUNK":
			if not is_host:
				_write_received_chunk(packet, from_uid)
		"SONG_FILE_END":
			if not is_host:
				_finish_received_file(packet, from_uid)
		"SONG_COMPLETE":
			if not is_host:
				_complete_song_receive(packet, from_uid)
		"SONG_TRANSFER_ERROR":
			if is_host:
				_cancel_song_send(
					from_uid, I18n.t("song_transfer_error_reason"))
			else:
				_fail_song_transfer(
					I18n.t("song_transfer_error_reason"), false)

func _start_song_send(uid: String, fingerprint: String) -> void:
	if not is_host or fingerprint.is_empty() \
			or fingerprint != String(selected_song.get("fingerprint", "")):
		return
	if _song_send_transfers.has(uid):
		return
	var source_song := find_local_song(fingerprint)
	if source_song.is_empty():
		_send_to(uid, {
			"type": "SONG_TRANSFER_ERROR",
			"error_code": "transfer_error",
			"message": "Transfer error",
		})
		return
	var manifest := _build_song_transfer_manifest(source_song, fingerprint)
	if manifest.is_empty():
		_send_to(uid, {
			"type": "SONG_TRANSFER_ERROR",
			"error_code": "transfer_error",
			"message": "Transfer error",
		})
		return
	var transfer_id := "%s-%s-%d" % [
		fingerprint.left(8), uid.left(8), Time.get_ticks_msec()]
	_song_send_transfers[uid] = {
		"manifest": manifest,
		"transfer_id": transfer_id,
		"phase": "queued",
		"file_index": 0,
		"file": null,
		"file_sent": 0,
		"total_sent": 0,
		"acked_total": 0,
		"pending_chunk": PackedByteArray(),
		"pending_offset": 0,
		"queued_tick": Time.get_ticks_msec(),
		"last_progress_tick": Time.get_ticks_msec(),
		"last_send_tick": 0,
	}
	_song_send_queue.append(uid)
	_activate_next_song_send()
	_refresh_host_song_transfer_state()
	lobby_changed.emit(_players_array(), room_data)

func _build_song_transfer_manifest(
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
		files.append(_song_manifest_file(source_path, source_path.get_file()))
	else:
		_collect_song_folder_files(base_path, base_path, files)
	if files.is_empty() or files.size() > 256:
		return {}
	var total_size := 0
	var entry_relative := ""
	for file in files:
		total_size += int(file.get("size", 0))
		if String(file.get("source_path", "")) == source_path:
			entry_relative = String(file.get("relative_path", ""))
	if entry_relative.is_empty() or total_size <= 0 \
			or total_size > MAX_SONG_TRANSFER_BYTES:
		return {}
	return {
		"name": String(source_song.get("display_name", source_path.get_file())),
		"fingerprint": fingerprint,
		"single_file": single_file,
		"entry_relative": entry_relative,
		"files": files,
		"total_size": total_size,
	}

func _song_manifest_file(source_path: String, relative_path: String) -> Dictionary:
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		return {}
	var size := file.get_length()
	file.close()
	return {
		"source_path": source_path,
		"relative_path": _safe_manifest_relative(relative_path),
		"size": size,
	}

func _collect_song_folder_files(
		base_path: String, current_path: String, result: Array[Dictionary]) -> void:
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
			_collect_song_folder_files(base_path, child_path, result)
			continue
		if child_name.ends_with(".import") or child_name.begins_with("."):
			continue
		var relative := child_path.trim_prefix(base_path).trim_prefix("/")
		var entry := _song_manifest_file(child_path, relative)
		if not entry.is_empty():
			result.append(entry)

func _public_song_manifest(manifest: Dictionary) -> Dictionary:
	var public_files: Array[Dictionary] = []
	for file in manifest.get("files", []):
		public_files.append({
			"relative_path": file.get("relative_path", ""),
			"size": int(file.get("size", 0)),
		})
	return {
		"type": "SONG_OFFER",
		"name": manifest.get("name", I18n.t("default_song_name")),
		"fingerprint": manifest.get("fingerprint", ""),
		"single_file": bool(manifest.get("single_file", false)),
		"entry_relative": manifest.get("entry_relative", ""),
		"files": public_files,
		"total_size": int(manifest.get("total_size", 0)),
	}

func _pump_song_transfers() -> void:
	if not is_host:
		return
	_expire_queued_song_sends()
	_activate_next_song_send()
	if _active_song_send_uid.is_empty() \
			or not _song_send_transfers.has(_active_song_send_uid):
		return
	var uid := _active_song_send_uid
	var transfer: Dictionary = _song_send_transfers[uid]
	var now := Time.get_ticks_msec()
	# Check timeouts before checking the channel. Previously a channel that
	# never opened (or stayed full) skipped this check forever and remained 0%.
	if now - int(transfer.get("last_progress_tick", now)) \
			> SONG_TRANSFER_STALL_TIMEOUT_MSEC:
		_cancel_song_send(uid, "Şarkı aktarım bağlantısı zaman aşımına uğradı.")
		return
	if not _connections.has(uid):
		_cancel_song_send(uid, "Oyuncunun bağlantısı kesildi.")
		return
	var connection: Dictionary = _connections[uid]
	var channel: WebRTCDataChannel = connection.get("transfer_channel", null)
	if channel == null or channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return

	var manifest: Dictionary = transfer["manifest"]
	var transfer_id := String(transfer.get("transfer_id", ""))
	var phase := String(transfer.get("phase", "queued"))
	if phase == "queued":
		transfer["phase"] = "offer"
		transfer["last_progress_tick"] = now
		_song_send_transfers[uid] = transfer
		phase = "offer"
	if phase == "offer":
		var offer := _public_song_manifest(manifest)
		offer["transfer_id"] = transfer_id
		if _send_transfer_to(uid, offer):
			transfer["phase"] = "wait_accept"
			transfer["last_send_tick"] = now
			_song_send_transfers[uid] = transfer
		return
	if phase == "wait_accept":
		if now - int(transfer.get("last_send_tick", 0)) \
				>= SONG_TRANSFER_RETRY_INTERVAL_MSEC:
			var retry_offer := _public_song_manifest(manifest)
			retry_offer["transfer_id"] = transfer_id
			if _send_transfer_to(uid, retry_offer):
				transfer["last_send_tick"] = now
				_song_send_transfers[uid] = transfer
		return

	var files: Array = manifest.get("files", [])
	var file_index := int(transfer.get("file_index", 0))
	if file_index >= files.size():
		if phase == "wait_complete":
			if now - int(transfer.get("last_send_tick", 0)) \
					>= SONG_TRANSFER_RETRY_INTERVAL_MSEC \
					and _send_transfer_to(uid, {
						"type": "SONG_COMPLETE",
						"transfer_id": transfer_id,
					}):
				transfer["last_send_tick"] = now
				_song_send_transfers[uid] = transfer
			return
		if _send_transfer_to(uid, {
			"type": "SONG_COMPLETE",
			"transfer_id": transfer_id,
		}):
			transfer["phase"] = "wait_complete"
			transfer["last_send_tick"] = now
			transfer["last_progress_tick"] = now
			_song_send_transfers[uid] = transfer
		return

	var file_info: Dictionary = files[file_index]
	if phase == "file_start":
		var source_file: FileAccess = transfer.get("file")
		if source_file == null:
			source_file = FileAccess.open(
				String(file_info.get("source_path", "")), FileAccess.READ)
			if source_file == null:
				_cancel_song_send(uid, "Şarkı dosyası okunamadı.")
				return
			transfer["file"] = source_file
			transfer["file_sent"] = 0
			transfer["pending_chunk"] = PackedByteArray()
		if _send_transfer_to(uid, {
			"type": "SONG_FILE_START",
			"transfer_id": transfer_id,
			"index": file_index,
		}):
			transfer["phase"] = "wait_file_ready"
			transfer["last_send_tick"] = now
			_song_send_transfers[uid] = transfer
		return
	if phase == "wait_file_ready":
		if now - int(transfer.get("last_send_tick", 0)) \
				>= SONG_TRANSFER_RETRY_INTERVAL_MSEC \
				and _send_transfer_to(uid, {
					"type": "SONG_FILE_START",
					"transfer_id": transfer_id,
					"index": file_index,
				}):
			transfer["last_send_tick"] = now
			_song_send_transfers[uid] = transfer
		return
	if phase != "chunks":
		return

	var source_file: FileAccess = transfer.get("file")
	if source_file == null:
		_cancel_song_send(uid, "Şarkı dosyası kapandı.")
		return
	var file_sent := int(transfer.get("file_sent", 0))
	var total_sent := int(transfer.get("total_sent", 0))
	var acked_total := int(transfer.get("acked_total", 0))
	var remaining := int(file_info.get("size", 0)) - file_sent
	if remaining > 0:
		if total_sent - acked_total >= SONG_TRANSFER_ACK_WINDOW_BYTES \
				or channel.get_buffered_amount() >= SONG_TRANSFER_BUFFER_LIMIT:
			return
		var chunk: PackedByteArray = transfer.get(
			"pending_chunk", PackedByteArray())
		var offset := int(transfer.get("pending_offset", file_sent))
		if chunk.is_empty():
			# Always seek from acknowledged state before reading. A failed
			# put_packet can no longer advance the file and silently drop data.
			chunk = _read_song_send_chunk(source_file, file_sent, remaining)
			if chunk.is_empty():
				_cancel_song_send(uid, "Şarkı dosyası eksik okundu.")
				return
			offset = file_sent
			transfer["pending_chunk"] = chunk
			transfer["pending_offset"] = offset
			_song_send_transfers[uid] = transfer
		if _send_transfer_to(uid, {
			"type": "SONG_CHUNK",
			"transfer_id": transfer_id,
			"index": file_index,
			"offset": offset,
			"data": chunk,
		}):
			transfer["file_sent"] = file_sent + chunk.size()
			transfer["total_sent"] = total_sent + chunk.size()
			transfer["pending_chunk"] = PackedByteArray()
			transfer["last_send_tick"] = now
			_song_send_transfers[uid] = transfer
		return

	# All bytes are queued, but the file isn't complete until the receiver has
	# acknowledged them. Progress and completion therefore reflect real writes.
	if acked_total < total_sent:
		return
	if _send_transfer_to(uid, {
		"type": "SONG_FILE_END",
		"transfer_id": transfer_id,
		"index": file_index,
	}):
		source_file.close()
		transfer["file"] = null
		transfer["file_index"] = file_index + 1
		transfer["phase"] = "file_start"
		transfer["last_progress_tick"] = now
		_song_send_transfers[uid] = transfer

func _read_song_send_chunk(source_file: FileAccess, offset: int,
		remaining: int) -> PackedByteArray:
	if source_file == null or remaining <= 0:
		return PackedByteArray()
	source_file.seek(offset)
	return source_file.get_buffer(
		mini(SONG_TRANSFER_CHUNK_SIZE, remaining))

func _activate_next_song_send() -> void:
	if not is_host or not _active_song_send_uid.is_empty():
		return
	for queued_uid in _song_send_queue.duplicate():
		if not _song_send_transfers.has(queued_uid):
			_song_send_queue.erase(queued_uid)
			continue
		var connection: Dictionary = _connections.get(queued_uid, {})
		var channel: WebRTCDataChannel = connection.get("transfer_channel", null)
		if channel == null or channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
			continue
		_active_song_send_uid = queued_uid
		_song_send_queue.erase(queued_uid)
		var transfer: Dictionary = _song_send_transfers[queued_uid]
		transfer["phase"] = "offer"
		transfer["last_progress_tick"] = Time.get_ticks_msec()
		_song_send_transfers[queued_uid] = transfer
		_refresh_host_song_transfer_state()
		return

func _expire_queued_song_sends() -> void:
	# Time spent behind another player's upload is legitimate and can be several
	# minutes for large songs. Only time the queue when it is ready to advance
	# but none of the waiting players has an open transfer channel.
	if not _active_song_send_uid.is_empty():
		return
	var now := Time.get_ticks_msec()
	for queued_uid in _song_send_queue.duplicate():
		if not _song_send_transfers.has(queued_uid):
			_song_send_queue.erase(queued_uid)
			continue
		var transfer: Dictionary = _song_send_transfers[queued_uid]
		var connection: Dictionary = _connections.get(queued_uid, {})
		var channel: WebRTCDataChannel = connection.get("transfer_channel", null)
		if channel != null \
				and channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			transfer.erase("channel_wait_tick")
			_song_send_transfers[queued_uid] = transfer
			continue
		if not transfer.has("channel_wait_tick"):
			transfer["channel_wait_tick"] = now
			_song_send_transfers[queued_uid] = transfer
			continue
		if now - int(transfer.get("channel_wait_tick", now)) \
				> SONG_TRANSFER_STALL_TIMEOUT_MSEC:
			_cancel_song_send(
				queued_uid, "Şarkı aktarım kanalı açılamadı.")
			return

func _refresh_host_song_transfer_state(final_detail: String = "") -> void:
	if not is_host:
		return
	if not _active_song_send_uid.is_empty() \
			and _song_send_transfers.has(_active_song_send_uid):
		var transfer: Dictionary = _song_send_transfers[_active_song_send_uid]
		var manifest: Dictionary = transfer.get("manifest", {})
		var progress := float(transfer.get("acked_total", 0)) / maxf(
			1.0, float(manifest.get("total_size", 1)))
		var player_name := String(players.get(
			_active_song_send_uid, {}).get("name", I18n.t("default_player_name")))
		var waiting := _song_send_queue.size()
		var detail := I18n.t("song_transfer_sending_player", [player_name])
		if waiting > 0:
			detail += I18n.t("song_transfer_queue_suffix", [waiting])
		_set_song_transfer_state(true, progress, detail)
		return
	if not _song_send_queue.is_empty():
		_set_song_transfer_state(
			true, 0.0,
			I18n.t("song_transfer_waiting_queue", [_song_send_queue.size()]))
		return
	_set_song_transfer_state(false, 1.0, final_detail)

func song_transfer_status_for(uid: String) -> String:
	if selected_song.is_empty() or not players.has(uid):
		return ""
	if bool(players[uid].get("song_ok", false)):
		return I18n.t("song_status_ready")
	if is_host:
		if uid == _active_song_send_uid \
				and _song_send_transfers.has(uid):
			return I18n.t("song_status_downloading")
		var queue_index := _song_send_queue.find(uid)
		if queue_index >= 0:
			return I18n.t("song_status_queued", [
				queue_index + 1, _song_send_queue.size()])
		return I18n.t("song_status_waiting")
	if uid == local_uid and song_transfer_active:
		return I18n.t("song_status_downloading")
	return I18n.t("song_status_waiting")

func _send_transfer_to(uid: String, packet: Dictionary) -> bool:
	if not _connections.has(uid):
		return false
	var channel: WebRTCDataChannel = _connections[uid].get(
		"transfer_channel", null)
	if channel == null \
			or channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return false
	return channel.put_packet(var_to_bytes(packet)) == OK

func _accept_song_transfer(uid: String, packet: Dictionary) -> void:
	if not _valid_song_send_ack(uid, packet):
		return
	var transfer: Dictionary = _song_send_transfers[uid]
	if String(packet.get("type", "")) == "SONG_ACCEPT":
		if String(transfer.get("phase", "")) == "wait_accept":
			transfer["phase"] = "file_start"
			transfer["last_progress_tick"] = Time.get_ticks_msec()
			_song_send_transfers[uid] = transfer
		return
	var index := int(packet.get("index", -1))
	if index != int(transfer.get("file_index", -1)):
		return
	var received_total := int(packet.get("total_received", -1))
	var acked_total := int(transfer.get("acked_total", 0))
	var total_sent := int(transfer.get("total_sent", 0))
	if received_total < acked_total or received_total > total_sent:
		return
	transfer["acked_total"] = received_total
	transfer["last_progress_tick"] = Time.get_ticks_msec()
	if String(transfer.get("phase", "")) == "wait_file_ready":
		transfer["phase"] = "chunks"
	_song_send_transfers[uid] = transfer
	_refresh_host_song_transfer_state()

func _complete_song_send(uid: String, packet: Dictionary = {}) -> void:
	if not _song_send_transfers.has(uid):
		return
	var transfer: Dictionary = _song_send_transfers[uid]
	if not packet.is_empty() \
			and String(packet.get("transfer_id", "")) != String(
				transfer.get("transfer_id", "")):
		return
	var file: FileAccess = transfer.get("file")
	if file:
		file.close()
	_song_send_transfers.erase(uid)
	_song_send_queue.erase(uid)
	if _active_song_send_uid == uid:
		_active_song_send_uid = ""
	var player_name := String(players.get(
		uid, {}).get("name", I18n.t("default_player_name")))
	_activate_next_song_send()
	_refresh_host_song_transfer_state(
		I18n.t("song_transfer_player_ready", [player_name]))
	lobby_changed.emit(_players_array(), room_data)

func _valid_song_send_ack(uid: String, packet: Dictionary) -> bool:
	return is_host and uid == _active_song_send_uid \
		and _song_send_transfers.has(uid) \
		and String(packet.get("transfer_id", "")) == String(
			_song_send_transfers[uid].get("transfer_id", ""))

func _begin_song_receive(offer: Dictionary, from_uid: String) -> void:
	if is_host:
		return
	var transfer_id := String(offer.get("transfer_id", ""))
	if transfer_id.is_empty():
		_fail_song_transfer("Geçersiz şarkı aktarım kimliği.", false)
		return
	if not _song_receive_transfer.is_empty():
		if String(_song_receive_transfer.get("transfer_id", "")) == transfer_id \
				and _valid_receive_sender(from_uid):
			_send_song_receive_ack("SONG_ACCEPT")
		return
	var fingerprint := String(offer.get("fingerprint", ""))
	if fingerprint != String(selected_song.get("fingerprint", "")):
		return
	var files_variant = offer.get("files", [])
	if not files_variant is Array or files_variant.is_empty() \
			or files_variant.size() > 256:
		_fail_song_transfer("Geçersiz dosya listesi.")
		return
	var total_size := int(offer.get("total_size", 0))
	if total_size <= 0 or total_size > MAX_SONG_TRANSFER_BYTES:
		_fail_song_transfer("Şarkı dosyası izin verilen boyutu aşıyor.")
		return
	var files: Array[Dictionary] = []
	var calculated_total := 0
	for file_variant in files_variant:
		if not file_variant is Dictionary:
			_fail_song_transfer("Geçersiz dosya bilgisi.")
			return
		var relative := _safe_manifest_relative(
			String(file_variant.get("relative_path", "")))
		var size := int(file_variant.get("size", -1))
		if relative.is_empty() or size < 0:
			_fail_song_transfer("Güvensiz dosya yolu.")
			return
		files.append({"relative_path": relative, "size": size})
		calculated_total += size
	if calculated_total != total_size:
		_fail_song_transfer("Şarkı boyutu doğrulanamadı.")
		return
	DirAccess.make_dir_recursive_absolute(SONG_TRANSFER_TEMP_DIR)
	var temp_root := SONG_TRANSFER_TEMP_DIR.path_join(
		"%s_%d" % [fingerprint.left(12), Time.get_ticks_msec()])
	DirAccess.make_dir_recursive_absolute(temp_root)
	_song_receive_transfer = {
		"from_uid": from_uid,
		"transfer_id": transfer_id,
		"name": String(offer.get("name", I18n.t("default_song_name"))),
		"fingerprint": fingerprint,
		"single_file": bool(offer.get("single_file", false)),
		"entry_relative": _safe_manifest_relative(
			String(offer.get("entry_relative", ""))),
		"files": files,
		"total_size": total_size,
		"total_received": 0,
		"current_index": -1,
		"current_received": 0,
		"file": null,
		"temp_root": temp_root,
		"last_progress_tick": Time.get_ticks_msec(),
		"last_ack_tick": 0,
	}
	_set_song_transfer_state(
		true, 0.0,
		I18n.t("song_transfer_downloading_name", [
			offer.get("name", I18n.t("default_song_name"))]))
	_send_song_receive_ack("SONG_ACCEPT")

func _begin_received_file(packet: Dictionary, from_uid: String) -> void:
	if not _valid_receive_packet(packet, from_uid):
		return
	var index := int(packet.get("index", -1))
	var expected := int(_song_receive_transfer.get("current_index", -1)) + 1
	var files: Array = _song_receive_transfer.get("files", [])
	if index == int(_song_receive_transfer.get("current_index", -1)):
		# Retried FILE_START packets must never truncate a partially received
		# file. Confirm the existing file and cumulative offset instead.
		_send_song_receive_ack("SONG_FILE_READY")
		return
	if index != expected or index < 0 or index >= files.size():
		_fail_song_transfer("Şarkı dosya sırası bozuldu.")
		return
	_close_received_file()
	var info: Dictionary = files[index]
	var destination := String(_song_receive_transfer["temp_root"]).path_join(
		String(info["relative_path"]))
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output == null:
		_fail_song_transfer("İndirilen şarkı kaydedilemedi.")
		return
	_song_receive_transfer["current_index"] = index
	_song_receive_transfer["current_received"] = 0
	_song_receive_transfer["file"] = output
	_song_receive_transfer["last_progress_tick"] = Time.get_ticks_msec()
	_send_song_receive_ack("SONG_FILE_READY")

func _write_received_chunk(packet: Dictionary, from_uid: String) -> void:
	if not _valid_receive_packet(packet, from_uid):
		return
	var index := int(packet.get("index", -1))
	if index != int(_song_receive_transfer.get("current_index", -1)):
		_fail_song_transfer("Şarkı parçası yanlış dosyaya geldi.")
		return
	var chunk: PackedByteArray = packet.get("data", PackedByteArray())
	if not chunk is PackedByteArray or chunk.is_empty() \
			or chunk.size() > SONG_TRANSFER_CHUNK_SIZE:
		_fail_song_transfer("Geçersiz şarkı parçası.")
		return
	var files: Array = _song_receive_transfer.get("files", [])
	var expected_size := int(files[index].get("size", 0))
	var offset := int(packet.get("offset", -1))
	var current_received := int(
		_song_receive_transfer.get("current_received", 0))
	if offset < current_received:
		# Ordered WebRTC is reliable, but a retried packet can arrive after a
		# reconnect/recovery ACK. It was already written; acknowledge it again.
		_send_song_receive_ack("SONG_ACK")
		return
	if offset != current_received:
		_fail_song_transfer("Şarkı parçası sırası bozuldu.")
		return
	var next_size: int = int(_song_receive_transfer.get("current_received", 0)) \
		+ chunk.size()
	if next_size > expected_size:
		_fail_song_transfer("Şarkı dosyası beklenenden büyük geldi.")
		return
	var output: FileAccess = _song_receive_transfer.get("file")
	if output == null:
		_fail_song_transfer("Şarkı hedef dosyası açık değil.")
		return
	output.store_buffer(chunk)
	_song_receive_transfer["current_received"] = next_size
	_song_receive_transfer["total_received"] = int(
		_song_receive_transfer.get("total_received", 0)) + chunk.size()
	_song_receive_transfer["last_progress_tick"] = Time.get_ticks_msec()
	_set_song_transfer_state(
		true,
		float(_song_receive_transfer["total_received"]) / maxf(
			1.0, float(_song_receive_transfer.get("total_size", 1))),
		I18n.t("song_transfer_downloading_name", [
			_song_receive_transfer.get("name", I18n.t("default_song_name"))]))
	_send_song_receive_ack("SONG_ACK")

func _finish_received_file(packet: Dictionary, from_uid: String) -> void:
	if not _valid_receive_packet(packet, from_uid):
		return
	var index := int(packet.get("index", -1))
	if index != int(_song_receive_transfer.get("current_index", -1)):
		_fail_song_transfer("Şarkı dosyası yanlış sırada tamamlandı.")
		return
	var files: Array = _song_receive_transfer.get("files", [])
	if int(_song_receive_transfer.get("current_received", -1)) \
			!= int(files[index].get("size", 0)):
		_fail_song_transfer("Şarkı dosyası eksik indirildi.")
		return
	_close_received_file()
	_song_receive_transfer["last_progress_tick"] = Time.get_ticks_msec()

func _complete_song_receive(packet: Dictionary, from_uid: String) -> void:
	var transfer_id := String(packet.get("transfer_id", ""))
	if _song_receive_transfer.is_empty() \
			and transfer_id == _last_completed_transfer_id \
			and from_uid == _last_completed_transfer_host_uid:
		_send_to(from_uid, {
			"type": "SONG_COMPLETE_ACK",
			"transfer_id": transfer_id,
		})
		return
	if not _valid_receive_packet(packet, from_uid):
		return
	_close_received_file()
	var files: Array = _song_receive_transfer.get("files", [])
	if int(_song_receive_transfer.get("current_index", -1)) != files.size() - 1 \
			or int(_song_receive_transfer.get("total_received", -1)) \
			!= int(_song_receive_transfer.get("total_size", 0)):
		_fail_song_transfer("Şarkı aktarımı tamamlanmadı.")
		return
	var entry_relative := String(_song_receive_transfer.get("entry_relative", ""))
	var temp_root := String(_song_receive_transfer.get("temp_root", ""))
	var temp_entry := temp_root.path_join(entry_relative)
	if not FileAccess.file_exists(temp_entry):
		_fail_song_transfer("İndirilen chart bulunamadı.")
		return
	DirAccess.make_dir_recursive_absolute(USER_SONGS_DIR)
	var final_entry := ""
	if bool(_song_receive_transfer.get("single_file", false)):
		var final_name := _safe_path_component(entry_relative.get_file())
		var desired := USER_SONGS_DIR.path_join(final_name)
		if FileAccess.file_exists(desired):
			desired = USER_SONGS_DIR.path_join(
				"%s_%s.%s" % [
					final_name.get_basename(),
					String(_song_receive_transfer["fingerprint"]).left(8),
					final_name.get_extension(),
				])
		var rename_error := DirAccess.rename_absolute(temp_entry, desired)
		if rename_error != OK:
			_fail_song_transfer("İndirilen şarkı taşınamadı.")
			return
		final_entry = desired
	else:
		var folder_name := _safe_path_component(
			String(_song_receive_transfer.get("name", "song")).get_basename())
		var final_root := USER_SONGS_DIR.path_join(
			"%s_%s" % [
				folder_name,
				String(_song_receive_transfer["fingerprint"]).left(8),
			])
		if DirAccess.dir_exists_absolute(final_root):
			final_root += "_%d" % Time.get_ticks_msec()
		var rename_error := DirAccess.rename_absolute(temp_root, final_root)
		if rename_error != OK:
			_fail_song_transfer("İndirilen şarkı klasörü taşınamadı.")
			return
		final_entry = final_root.path_join(entry_relative)
	var expected_fingerprint := String(_song_receive_transfer.get("fingerprint", ""))
	var completed_transfer_id := String(
		_song_receive_transfer.get("transfer_id", ""))
	var downloaded_song := {
		"path": final_entry,
		"display_name": String(_song_receive_transfer.get(
			"name", I18n.t("default_song_name"))),
	}
	if song_fingerprint(final_entry) != expected_fingerprint:
		_requested_song_fingerprint = ""
		_fail_song_transfer("İndirilen şarkının doğrulaması başarısız.")
		return
	_song_receive_transfer.clear()
	song_catalog.append(downloaded_song)
	_requested_song_fingerprint = ""
	_last_completed_transfer_id = completed_transfer_id
	_last_completed_transfer_host_uid = from_uid
	_send_to(from_uid, {
		"type": "SONG_COMPLETE_ACK",
		"transfer_id": completed_transfer_id,
	})
	update_local_player({"song_ok": true, "ready": false})
	_set_song_transfer_state(false, 1.0, I18n.t("song_transfer_complete"))
	song_transfer_completed.emit(downloaded_song)
	lobby_changed.emit(_players_array(), room_data)

func _valid_receive_sender(uid: String) -> bool:
	return not _song_receive_transfer.is_empty() \
		and String(_song_receive_transfer.get("from_uid", "")) == uid

func _valid_receive_packet(packet: Dictionary, uid: String) -> bool:
	return _valid_receive_sender(uid) \
		and String(packet.get("transfer_id", "")) == String(
			_song_receive_transfer.get("transfer_id", ""))

func _send_song_receive_ack(type: String) -> void:
	if _song_receive_transfer.is_empty():
		return
	var from_uid := String(_song_receive_transfer.get("from_uid", ""))
	if from_uid.is_empty():
		return
	_send_to(from_uid, {
		"type": type,
		"transfer_id": String(_song_receive_transfer.get("transfer_id", "")),
		"index": int(_song_receive_transfer.get("current_index", -1)),
		"file_received": int(
			_song_receive_transfer.get("current_received", 0)),
		"total_received": int(
			_song_receive_transfer.get("total_received", 0)),
	})
	_song_receive_transfer["last_ack_tick"] = Time.get_ticks_msec()

func _pump_song_receive_ack() -> void:
	if is_host or _song_receive_transfer.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - int(_song_receive_transfer.get("last_ack_tick", 0)) \
			< SONG_TRANSFER_RETRY_INTERVAL_MSEC:
		return
	if int(_song_receive_transfer.get("current_index", -1)) < 0:
		_send_song_receive_ack("SONG_ACCEPT")
	elif _song_receive_transfer.get("file") != null:
		_send_song_receive_ack("SONG_ACK")

func _close_received_file() -> void:
	if _song_receive_transfer.is_empty():
		return
	var output: FileAccess = _song_receive_transfer.get("file")
	if output:
		output.close()
	_song_receive_transfer["file"] = null

func _cancel_song_send(uid: String, message: String) -> void:
	push_warning("Song transfer send failed for %s: %s" % [uid, message])
	var public_reason := I18n.t("song_transfer_error_reason")
	if _song_send_transfers.has(uid):
		var transfer: Dictionary = _song_send_transfers[uid]
		var file: FileAccess = transfer.get("file")
		if file:
			file.close()
		_song_send_transfers.erase(uid)
	_song_send_queue.erase(uid)
	if _active_song_send_uid == uid:
		_active_song_send_uid = ""
	_send_to(uid, {
		"type": "SONG_TRANSFER_ERROR",
		"error_code": "transfer_error",
		"message": "Transfer error",
	})
	_activate_next_song_send()
	_refresh_host_song_transfer_state(
		I18n.t("song_transfer_failed", [public_reason]))
	lobby_changed.emit(_players_array(), room_data)

func _fail_song_transfer(message: String, notify_host: bool = true) -> void:
	push_warning("Song transfer receive failed: %s" % message)
	var public_reason := I18n.t("song_transfer_timeout") \
		if message == I18n.t("song_transfer_timeout") \
		else I18n.t("song_transfer_error_reason")
	var from_uid := String(_song_receive_transfer.get("from_uid", ""))
	var transfer_id := String(_song_receive_transfer.get("transfer_id", ""))
	if notify_host and not from_uid.is_empty():
		_send_to(from_uid, {
			"type": "SONG_TRANSFER_ERROR",
			"transfer_id": transfer_id,
			"error_code": "transfer_error",
			"message": "Transfer error",
		})
	_close_received_file()
	_song_receive_transfer.clear()
	_requested_song_fingerprint = ""
	_set_song_transfer_state(
		false, 0.0, I18n.t("song_transfer_failed", [public_reason]))
	_fail(I18n.t("song_transfer_failed", [public_reason]), false)

func _set_song_transfer_state(
		active: bool, progress: float, detail: String) -> void:
	song_transfer_active = active
	song_transfer_progress = clampf(progress, 0.0, 1.0)
	song_transfer_detail = detail
	song_transfer_progress_changed.emit(
		song_transfer_progress, song_transfer_detail, song_transfer_active)

func _check_song_transfer_timeout() -> void:
	if is_host or not song_transfer_active:
		return
	if _cloud_download_active:
		return
	var now := Time.get_ticks_msec()
	if not _song_receive_transfer.is_empty():
		if now - int(_song_receive_transfer.get("last_progress_tick", now)) \
				> SONG_TRANSFER_STALL_TIMEOUT_MSEC:
			_fail_song_transfer(I18n.t("song_transfer_timeout"))
		return
	if not _requested_song_fingerprint.is_empty() \
			and now - _song_request_tick_msec >= SONG_REQUEST_RETRY_INTERVAL_MSEC:
		_send_packet({
			"type": "SONG_REQUEST",
			"fingerprint": _requested_song_fingerprint,
		})
		_song_request_tick_msec = now

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

func _on_channel_open(uid: String) -> void:
	var player_name := String(players.get(
		uid, {}).get("name", I18n.t("default_player_name")))
	_set_state(session_state, I18n.t("mp_player_connected", [player_name]))
	if is_host:
		_send_to(uid, {"type": "LOBBY", "song": selected_song, "players": _players_array()})
		if match_loading and not _match_config.is_empty() \
				and uid in _match_participant_uids:
			if _match_entry_started:
				_send_to(uid, {
					"type": "ENTER_MATCH",
					"match_id": _match_id,
				})
			else:
				_send_to(uid, {
					"type": "PREPARE",
					"match_id": _match_id,
					"config": _match_config,
				})
		elif match_active and not _match_start_packet.is_empty() \
				and uid in _match_participant_uids:
			_send_to(uid, _match_start_packet)
	else:
		_send_to(uid, {"type": "PING", "client_tick": Time.get_ticks_msec()})
		if not _requested_song_fingerprint.is_empty() \
				and _song_receive_transfer.is_empty() \
				and not _cloud_download_active:
			_send_to(uid, {
				"type": "SONG_REQUEST",
				"fingerprint": _requested_song_fingerprint,
			})
			_song_request_tick_msec = Time.get_ticks_msec()

func _receive_packet(packet: Dictionary, from_uid: String) -> void:
	var type := String(packet.get("type", ""))
	match type:
		"PING":
			if is_host:
				_send_to(from_uid, {
					"type": "PONG",
					"client_tick": int(packet.get("client_tick", 0)),
					"host_tick": Time.get_ticks_msec(),
				})
		"PONG":
			var now := Time.get_ticks_msec()
			var sent := int(packet.get("client_tick", now))
			var rtt := float(now - sent)
			if rtt < _best_clock_rtt:
				_best_clock_rtt = rtt
				_clock_offset_msec = float(packet.get("host_tick", now)) + rtt * 0.5 - now
		"PLAYER_UPDATE":
			if is_host:
				var player: Dictionary = packet.get("player", {})
				var uid := String(player.get("uid", from_uid))
				if uid == from_uid:
					players[uid] = player
					if bool(player.get("song_ok", false)) \
							and _song_send_transfers.has(uid):
						_complete_song_send(uid)
					_send_packet({"type": "LOBBY", "song": selected_song, "players": _players_array()})
		"LOBBY":
			if not is_host:
				selected_song = packet.get("song", {})
				for player in packet.get("players", []):
					players[String(player.get("uid", ""))] = player
				_update_local_song_match()
				lobby_changed.emit(_players_array(), room_data)
		"PREPARE":
			if not is_host:
				_receive_match_prepare(packet, from_uid)
		"PREPARE_ACK":
			if is_host \
					and String(packet.get("match_id", "")) == _match_id \
					and from_uid in _match_participant_uids:
				_prepare_acked[from_uid] = true
				_maybe_enter_match()
		"PREPARE_ERROR":
			if is_host and String(packet.get("match_id", "")) == _match_id:
				var failed_name := String(players.get(
					from_uid, {}).get("name", I18n.t("default_player_name")))
				push_warning("Peer %s could not prepare: %s" % [
					from_uid, String(packet.get("error_code", "unknown"))])
				_fail(I18n.t("mp_prepare_failed", [failed_name]), false)
		"ENTER_MATCH":
			if not is_host:
				_receive_match_enter(packet, from_uid)
		"SONG_REQUEST":
			if is_host:
				_start_song_send(
					from_uid, String(packet.get("fingerprint", "")))
		"SONG_CLOUD_READY":
			if not is_host:
				var cloud_fingerprint := String(packet.get("fingerprint", ""))
				if cloud_fingerprint == String(
						selected_song.get("fingerprint", "")) \
						and find_local_song(cloud_fingerprint).is_empty() \
						and not _cloud_download_active \
						and not _cloud_failed_fingerprints.has(
							cloud_fingerprint):
					_begin_cloud_song_download(cloud_fingerprint)
		"SONG_ACCEPT", "SONG_FILE_READY", "SONG_ACK":
			if is_host:
				_accept_song_transfer(from_uid, packet)
		"SONG_COMPLETE_ACK":
			if is_host:
				_complete_song_send(from_uid, packet)
		"SONG_TRANSFER_ERROR":
			if is_host:
				_cancel_song_send(
					from_uid, I18n.t("song_transfer_error_reason"))
			else:
				_fail_song_transfer(
					I18n.t("song_transfer_error_reason"), false)
		"LOADED":
			if is_host and String(packet.get("uid", "")) == from_uid \
					and String(packet.get("match_id", "")) == _match_id \
					and from_uid in _match_participant_uids:
				_loaded_players[from_uid] = true
				_maybe_schedule_start()
		"START":
			if not is_host:
				_receive_match_start(packet, from_uid)
		"START_ACK":
			if is_host \
					and String(packet.get("match_id", "")) == _match_id \
					and from_uid in _match_participant_uids:
				_start_acked[from_uid] = true
		"GAME_STATE":
			if is_host:
				var state: Dictionary = packet.get("state", {})
				if String(state.get("uid", "")) == from_uid:
					_accept_game_state(state)
		"SNAPSHOT":
			if not is_host:
				latest_snapshot = packet.get("snapshot", {})
				scoreboard_changed.emit(latest_snapshot)
		"FINISH":
			if is_host:
				var state: Dictionary = packet.get("state", {})
				_accept_game_state(state)
				_finished_players[from_uid] = true
				_broadcast_snapshot()
		"BAND_FAIL":
			if not is_host and not _band_failed:
				_band_failed = true
				band_failed.emit()

func _prepare_local_match(config: Dictionary) -> void:
	var song_desc: Dictionary = config.get("song", {})
	_player_state_elapsed = 0.0
	_snapshot_elapsed = 0.0
	_pending_local_state.clear()
	for participant in config.get("players", []):
		if participant is Dictionary:
			players[String(participant.get("uid", ""))] = participant
	var local_song := find_local_song(String(song_desc.get("fingerprint", "")))
	if local_song.is_empty():
		match_loading = false
		if not is_host:
			_send_packet({
				"type": "PREPARE_ERROR",
				"match_id": _match_id,
				"error_code": "song_missing",
				"message": "Selected song was not found on this device.",
			})
		_fail(I18n.t("mp_song_missing_local"))
		return
	var local_player: Dictionary = players.get(local_uid, {})
	GameScript.song_source = String(local_song.get("path", ""))
	GameScript.song_difficulty = String(local_player.get("difficulty", "Expert"))
	GameScript.song_instrument = String(local_player.get("instrument", "guitar"))
	GameScript.song_available_instruments = song_desc.get("instruments", {})
	GameScript.song_mode = String(song_desc.get("mode", "guitar"))
	GameScript.song_preset = String(song_desc.get("preset", "Tiles"))
	match_loading = true
	match_prepare_requested.emit(config)
	var change_error := get_tree().change_scene_to_file("res://scenes/game.tscn")
	if change_error != OK:
		match_loading = false
		if not is_host:
			_send_packet({
				"type": "PREPARE_ERROR",
				"match_id": _match_id,
				"error_code": "game_screen_failed",
				"message": "Could not open the game screen.",
			})
		_fail(I18n.t("mp_game_screen_failed"), false)

func _maybe_schedule_start() -> void:
	if not is_host or match_active or _match_participant_uids.is_empty():
		return
	if not _all_match_participants_recorded(_loaded_players):
		return
	var delay_msec := 4500
	var host_tick := Time.get_ticks_msec() + delay_msec
	start_local_tick_msec = host_tick
	match_loading = false
	match_active = true
	_match_start_packet = {
		"type": "START",
		"match_id": _match_id,
		"host_tick": host_tick,
		"delay_msec": delay_msec,
	}
	_start_acked.clear()
	_start_acked[local_uid] = true
	_last_match_handshake_tick = 0
	_firebase("PATCH", "rooms/%s/meta" % room_code, {"status": "playing"})
	_send_start_to_missing()
	match_start_scheduled.emit(start_local_tick_msec)

func _receive_match_prepare(packet: Dictionary, from_uid: String) -> void:
	var config_variant = packet.get("config", {})
	if not config_variant is Dictionary:
		return
	var config: Dictionary = config_variant
	var incoming_match_id := String(
		packet.get("match_id", config.get("match_id", "")))
	if incoming_match_id.is_empty():
		return
	if _match_id == incoming_match_id:
		_send_to(from_uid, {
			"type": "PREPARE_ACK",
			"match_id": _match_id,
			"uid": local_uid,
		})
		if _local_game_loaded:
			_send_to(from_uid, {
				"type": "LOADED",
				"match_id": _match_id,
				"uid": local_uid,
			})
		return
	if match_active or match_loading:
		return
	_match_id = incoming_match_id
	_match_config = config.duplicate(true)
	_match_participant_uids.clear()
	for participant in config.get("players", []):
		if participant is Dictionary:
			_match_participant_uids.append(String(participant.get("uid", "")))
	if local_uid not in _match_participant_uids:
		_match_id = ""
		_match_config.clear()
		return
	_local_game_loaded = false
	match_loading = true
	_send_to(from_uid, {
		"type": "PREPARE_ACK",
		"match_id": _match_id,
		"uid": local_uid,
	})

func _receive_match_enter(packet: Dictionary, from_uid: String) -> void:
	if String(packet.get("match_id", "")) != _match_id \
			or _match_config.is_empty():
		return
	if _match_entry_started:
		if _local_game_loaded:
			_send_to(from_uid, {
				"type": "LOADED",
				"match_id": _match_id,
				"uid": local_uid,
			})
		return
	_match_entry_started = true
	_prepare_local_match(_match_config)

func _maybe_enter_match() -> void:
	if not is_host or _match_entry_started \
			or _match_participant_uids.is_empty():
		return
	if not _all_match_participants_recorded(_prepare_acked):
		return
	_match_entry_started = true
	_send_enter_to_unloaded()
	_prepare_local_match(_match_config)

func _all_match_participants_recorded(records: Dictionary) -> bool:
	if _match_participant_uids.is_empty():
		return false
	for uid in _match_participant_uids:
		if not records.has(uid):
			return false
	return true

func _receive_match_start(packet: Dictionary, from_uid: String) -> void:
	var incoming_match_id := String(packet.get("match_id", ""))
	if incoming_match_id.is_empty() or incoming_match_id != _match_id:
		return
	_send_to(from_uid, {
		"type": "START_ACK",
		"match_id": _match_id,
		"uid": local_uid,
	})
	if match_active and start_local_tick_msec > 0:
		return
	var delay := int(packet.get("delay_msec", 4500))
	var host_tick := int(packet.get("host_tick", 0))
	if host_tick > 0 and _best_clock_rtt != INF:
		start_local_tick_msec = int(float(host_tick) - _clock_offset_msec)
	else:
		var transit := 0.0 if _best_clock_rtt == INF else _best_clock_rtt * 0.5
		start_local_tick_msec = Time.get_ticks_msec() + maxi(
			500, int(delay - transit))
	match_loading = false
	match_active = true
	match_start_scheduled.emit(start_local_tick_msec)

func _pump_match_handshake() -> void:
	if _match_id.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - _last_match_handshake_tick < MATCH_HANDSHAKE_INTERVAL_MSEC:
		return
	_last_match_handshake_tick = now
	if is_host:
		if match_loading:
			if _match_entry_started:
				_send_enter_to_unloaded()
			else:
				_send_prepare_to_missing()
				_maybe_enter_match()
		elif match_active and not _match_start_packet.is_empty():
			_send_start_to_missing()
		return
	if match_loading and _local_game_loaded:
		_send_packet({
			"type": "LOADED",
			"match_id": _match_id,
			"uid": local_uid,
		})

func _send_prepare_to_missing() -> void:
	if not is_host or _match_config.is_empty():
		return
	for uid in _match_participant_uids:
		if uid == local_uid or _prepare_acked.has(uid):
			continue
		_send_to(uid, {
			"type": "PREPARE",
			"match_id": _match_id,
			"config": _match_config,
		})

func _send_start_to_missing() -> void:
	if not is_host or _match_start_packet.is_empty():
		return
	for uid in _match_participant_uids:
		if uid == local_uid or _start_acked.has(uid):
			continue
		_send_to(uid, _match_start_packet)

func _send_enter_to_unloaded() -> void:
	if not is_host:
		return
	for uid in _match_participant_uids:
		if uid == local_uid or _loaded_players.has(uid):
			continue
		_send_to(uid, {
			"type": "ENTER_MATCH",
			"match_id": _match_id,
		})

func _accept_game_state(state: Dictionary) -> void:
	var uid := String(state.get("uid", ""))
	if not players.has(uid):
		return
	var previous: Dictionary = _host_scores.get(uid, {})
	if not previous.is_empty() and int(state.get("seq", 0)) <= int(previous.get("seq", -1)):
		return
	var safe := state.duplicate(true)
	safe["name"] = players[uid].get(
		"name", I18n.t("default_player_name"))
	safe["instrument"] = players[uid].get("instrument", "")
	if not previous.is_empty():
		safe["score"] = maxi(int(previous.get("score", 0)), int(safe.get("score", 0)))
	_host_scores[uid] = safe

func _broadcast_snapshot() -> void:
	if not is_host:
		return
	var rows: Array = []
	var total_score := 0
	var health_total := 0.0
	for uid in players:
		var state: Dictionary = _host_scores.get(uid, {
			"uid": uid,
			"name": players[uid].get(
				"name", I18n.t("default_player_name")),
			"score": 0, "combo": 0, "health": 0.5})
		rows.append(state)
		total_score += int(state.get("score", 0))
		health_total += float(state.get("health", 0.5))
	latest_snapshot = {
		"mode": room_mode,
		"players": rows,
		"total_score": total_score,
		"band_health": health_total / maxf(1.0, float(rows.size())),
		"host_tick": Time.get_ticks_msec(),
	}
	_send_packet({"type": "SNAPSHOT", "snapshot": latest_snapshot})
	scoreboard_changed.emit(latest_snapshot)
	if room_mode == "band" and not _band_failed \
			and _host_scores.size() == players.size() \
			and float(latest_snapshot["band_health"]) <= 0.0:
		var progressed := true
		for state in _host_scores.values():
			if int(state.get("song_ms", 0)) < 3000:
				progressed = false
				break
		if progressed:
			_band_failed = true
			_send_packet({"type": "BAND_FAIL"})
			band_failed.emit()

func _send_packet(packet: Dictionary) -> void:
	if is_host:
		for uid in _connections:
			_send_to(String(uid), packet)
	else:
		for uid in _connections:
			_send_to(String(uid), packet)
			break

func _send_to(uid: String, packet: Dictionary) -> bool:
	if not _connections.has(uid):
		return false
	var connection: Dictionary = _connections[uid]
	var channel: WebRTCDataChannel = connection["channel"]
	if String(packet.get("type", "")) in REALTIME_PACKET_TYPES:
		var realtime_channel: WebRTCDataChannel = connection.get(
			"realtime_channel", channel)
		if realtime_channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			channel = realtime_channel
	if channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		# JSON keeps the realtime channel compatible with v0.3.3 and older
		# clients. The traffic is tiny (10 state packets / 5 snapshots a second);
		# avoiding mixed-protocol decode errors matters much more than the small
		# binary size saving.
		return channel.put_packet(JSON.stringify(packet).to_utf8_buffer()) == OK
	return false

func _has_open_channel() -> bool:
	for connection in _connections.values():
		if bool(connection.get("open", false)):
			return true
	return false

func _new_player(uid: String, name: String, host: bool) -> Dictionary:
	return {
		"uid": uid,
		"name": name,
		"host": host,
		"ready": false,
		"song_ok": false,
		"instrument": "",
		"difficulty": "Expert",
		"game_mode": "guitar",
		"preset": "Tiles",
		"joined_at": int(Time.get_unix_time_from_system() * 1000.0),
	}

func _players_array() -> Array:
	var result: Array = []
	for uid in players:
		result.append(players[uid])
	result.sort_custom(func(a, b):
		if bool(a.get("host", false)) != bool(b.get("host", false)):
			return bool(a.get("host", false))
		return String(a.get("name", "")) < String(b.get("name", "")))
	return result

func _ensure_auth() -> bool:
	if not _id_token.is_empty() and not local_uid.is_empty():
		return true
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=%s" % _api_key.uri_encode()
	var result := await _http_json(url, "POST", {"returnSecureToken": true})
	if not result.get("ok", false):
		_fail(I18n.t("mp_auth_failed"))
		return false
	var data: Dictionary = result.get("data", {})
	_id_token = String(data.get("idToken", ""))
	local_uid = String(data.get("localId", ""))
	return not _id_token.is_empty() and not local_uid.is_empty()

func _firebase(method: String, path: String, body = null) -> Dictionary:
	if _database_url.is_empty():
		return {"ok": false, "error": I18n.t("mp_firebase_missing")}
	var url := "%s/%s.json" % [_database_url, path]
	if not _id_token.is_empty():
		url += "?auth=%s" % _id_token.uri_encode()
	return await _http_json(url, method, body)

func _http_json(url: String, method: String, body = null) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 15.0
	add_child(request)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var http_method := HTTPClient.METHOD_GET
	match method:
		"POST": http_method = HTTPClient.METHOD_POST
		"PUT": http_method = HTTPClient.METHOD_PUT
		"PATCH": http_method = HTTPClient.METHOD_PATCH
		"DELETE": http_method = HTTPClient.METHOD_DELETE
	var payload := "" if body == null else JSON.stringify(body)
	var start_error := request.request(url, headers, http_method, payload)
	if start_error != OK:
		request.queue_free()
		return {"ok": false, "error": error_string(start_error)}
	var response: Array = await request.request_completed
	request.queue_free()
	var response_code := int(response[1])
	var text := (response[3] as PackedByteArray).get_string_from_utf8()
	var data = null
	if not text.is_empty():
		data = JSON.parse_string(text)
	var ok := response_code >= 200 and response_code < 300
	return {
		"ok": ok,
		"code": response_code,
		"data": data,
		"error": "" if ok else text,
	}

func _set_state(value: String, detail: String) -> void:
	session_state = value
	state_changed.emit(value, detail)

func _fail(message: String, fatal: bool = true) -> void:
	session_error.emit(message)
	state_changed.emit("error", message)
	if fatal:
		session_state = "error"

func _reset_session() -> void:
	_reset_song_transfers()
	_close_connections()
	session_state = "idle"
	room_code = ""
	room_mode = "battle"
	is_host = false
	players.clear()
	room_data.clear()
	selected_song.clear()
	match_active = false
	match_loading = false
	start_local_tick_msec = 0
	latest_snapshot.clear()
	_seen_remote_ice.clear()
	_host_scores.clear()
	_loaded_players.clear()
	_finished_players.clear()
	_match_id = ""
	_match_config.clear()
	_match_participant_uids.clear()
	_prepare_acked.clear()
	_start_acked.clear()
	_match_start_packet.clear()
	_last_match_handshake_tick = 0
	_local_game_loaded = false
	_match_entry_started = false
	_pending_local_state.clear()
	_connection_poll_elapsed = 0.0
	_player_state_elapsed = 0.0
	_snapshot_elapsed = 0.0
	_band_failed = false
	_last_room_status = ""
	_poll_busy = false

func _reset_song_transfers() -> void:
	if _cloud_transfer != null:
		_cloud_transfer.cancel()
	_cloud_upload_fingerprint = ""
	_cloud_download_fingerprint = ""
	_cloud_download_active = false
	_cloud_failed_fingerprints.clear()
	for transfer_variant in _song_send_transfers.values():
		var transfer: Dictionary = transfer_variant
		var source_file: FileAccess = transfer.get("file")
		if source_file:
			source_file.close()
	_song_send_transfers.clear()
	_song_send_queue.clear()
	_active_song_send_uid = ""
	_close_received_file()
	_song_receive_transfer.clear()
	_last_completed_transfer_id = ""
	_last_completed_transfer_host_uid = ""
	_requested_song_fingerprint = ""
	_song_request_tick_msec = 0
	song_transfer_active = false
	song_transfer_progress = 0.0
	song_transfer_detail = ""
	song_transfer_progress_changed.emit(0.0, "", false)

func _close_connections() -> void:
	for connection in _connections.values():
		var peer: WebRTCPeerConnection = connection.get("peer")
		if peer:
			peer.close()
	_connections.clear()

func _generate_room_code() -> String:
	const CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code := ""
	for _i in range(6):
		code += CHARS[randi_range(0, CHARS.length() - 1)]
	return code

func _clean_code(value: String) -> String:
	var result := ""
	for character in value.to_upper():
		if character in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789":
			result += character
	return result.left(6)

func _clean_name(value: String) -> String:
	var clean := value.strip_edges().left(18)
	return clean if not clean.is_empty() else I18n.t("default_player_name")

func _is_audio_file(file_name: String) -> bool:
	var lower := file_name.to_lower()
	return lower.ends_with(".ogg") or lower.ends_with(".opus") \
		or lower.ends_with(".mp3") or lower.ends_with(".wav") \
		or lower.ends_with(".mogg")
