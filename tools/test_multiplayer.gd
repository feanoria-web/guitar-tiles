extends SceneTree

func _initialize() -> void:
	var session = root.get_node("BattleSession")
	session.is_host = true
	session.session_state = "lobby"
	session.local_uid = "p1"
	session.selected_song = {"fingerprint": "test"}

	session.room_mode = "battle"
	session.players = {
		"p1": _player("p1", "guitar"),
		"p2": _player("p2", "guitar"),
		"p3": _player("p3", "drums"),
		"p4": _player("p4", "guitar"),
	}
	session._connections = {
		"p2": {"open": true},
		"p3": {"open": true},
		"p4": {"open": true},
	}
	_check(bool(session.can_start_match().get("ok", false)),
		"Battle must allow 2-4 players and duplicate instruments")

	session._connections["p3"]["open"] = false
	_check(not bool(session.can_start_match().get("ok", false)),
		"Match must wait until every participant control channel is open")
	session._connections["p3"]["open"] = true

	session._match_participant_uids.assign(["p1", "p2", "p3"])
	_check(not session._all_match_participants_recorded({
		"p1": true,
		"p2": true,
	}), "Match entry must wait for every participant's PREPARE_ACK")
	session.players.erase("p3")
	_check(not session._all_match_participants_recorded({
		"p1": true,
		"p2": true,
	}), "A changing lobby list must not drop a participant from the handshake")
	_check(session._all_match_participants_recorded({
		"p1": true,
		"p2": true,
		"p3": true,
	}), "Match entry must continue once the snapshotted participants all ACK")
	session.players["p3"] = _player("p3", "drums")
	_test_retryable_chunk_read(session)

	session.room_mode = "band"
	_check(not bool(session.can_start_match().get("ok", false)),
		"Band must reject duplicate roles")

	session.players["p2"]["instrument"] = "bass"
	session.players["p4"]["instrument"] = "keys"
	_check(bool(session.can_start_match().get("ok", false)),
		"Band must allow four unique roles")

	session.players.erase("p4")
	session.players.erase("p3")
	session.players.erase("p2")
	session._connections.clear()
	_check(not bool(session.can_start_match().get("ok", false)),
		"Both modes must require at least two players")

	var original_room := "ABC123"
	session.room_code = original_room
	session.room_mode = "battle"
	session.is_host = true
	session.session_state = "lobby"
	session.join_room(original_room, "Host")
	_check(session.room_code == original_room and session.is_host,
		"Host joining their own room must not reset the active host session")

	print("Multiplayer rules: PASS")
	quit(0)

func _test_retryable_chunk_read(session: Node) -> void:
	var test_path := "user://riffline-transfer-read-test.bin"
	var expected := PackedByteArray()
	for value in range(96):
		expected.append(value)
	var output := FileAccess.open(test_path, FileAccess.WRITE)
	_check(output != null, "Transfer read test file must be writable")
	output.store_buffer(expected)
	output.close()
	var input := FileAccess.open(test_path, FileAccess.READ)
	_check(input != null, "Transfer read test file must be readable")
	input.get_buffer(48) # Simulate a failed send after the file cursor advanced.
	var retried: PackedByteArray = session._read_song_send_chunk(input, 0, 32)
	_check(retried == expected.slice(0, 32),
		"A failed put_packet must retry the exact same file bytes")
	var next: PackedByteArray = session._read_song_send_chunk(input, 32, 32)
	_check(next == expected.slice(32, 64),
		"The acknowledged offset must select the following chunk")
	input.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))

func _player(uid: String, instrument: String) -> Dictionary:
	return {
		"uid": uid,
		"name": uid,
		"host": uid == "p1",
		"ready": true,
		"song_ok": true,
		"instrument": instrument,
	}

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
