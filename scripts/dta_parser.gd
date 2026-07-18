class_name DtaParser
extends RefCounted

## Parses Rock Band songs.dta metadata files (Lisp-like format).
## Extracts song name, artist, track→channel mapping, and other metadata.

var song_name: String = ""
var artist: String = ""
var midi_file: String = ""
var year: int = 0
var genre: String = ""
var vocal_parts: int = 1
var song_length_ms: int = 0
var preview_start_ms: int = 0
var preview_end_ms: int = 0

# Channel mapping: instrument -> Array of channel indices
var track_channels: Dictionary = {}  # e.g. {"drum": [0,1,2,3,4,5], "bass": [6], ...}
var crowd_channels: Array = []
var pans: Array = []   # float per channel
var vols: Array = []   # float per channel
var total_channels: int = 0

# Difficulty ranks
var ranks: Dictionary = {}  # e.g. {"drum": 220, "guitar": 80, ...}

func parse(text: String) -> bool:
	var tokens := _tokenize(text)
	if tokens.is_empty():
		push_error("DtaParser: empty/invalid DTA")
		return false
	var tree := _parse_tokens(tokens)
	if tree.is_empty():
		push_error("DtaParser: parse failed")
		return false
	_extract_metadata(tree)
	return song_name != "" or artist != ""

# --- Tokenizer ---
func _tokenize(text: String) -> Array[String]:
	var tokens: Array[String] = []
	var i := 0
	var length := text.length()

	while i < length:
		var c := text[i]

		# Skip whitespace
		if c == " " or c == "\t" or c == "\n" or c == "\r":
			i += 1
			continue

		# Line comment: ; or //
		if c == ";":
			while i < length and text[i] != "\n":
				i += 1
			continue
		if c == "/" and i + 1 < length and text[i + 1] == "/":
			while i < length and text[i] != "\n":
				i += 1
			continue

		# Block comment: /* ... */
		if c == "/" and i + 1 < length and text[i + 1] == "*":
			i += 2
			while i + 1 < length:
				if text[i] == "*" and text[i + 1] == "/":
					i += 2
					break
				i += 1
			continue

		# Delimiters
		if c == "(" or c == ")" or c == "{" or c == "}" or c == "[" or c == "]":
			tokens.append(c)
			i += 1
			continue

		# Quoted string: "..."
		if c == "\"":
			var s := ""
			i += 1
			while i < length and text[i] != "\"":
				if text[i] == "\\" and i + 1 < length:
					if text[i + 1] == "n":
						s += "\n"
					elif text[i + 1] == "q":
						s += "\""
					else:
						s += text[i + 1]
					i += 2
				else:
					s += text[i]
					i += 1
			i += 1  # skip closing quote
			tokens.append("\"" + s + "\"")  # prefix with " to mark as string
			continue

		# Quoted symbol: '...'
		if c == "'":
			var s := ""
			i += 1
			while i < length and text[i] != "'":
				if text[i] == "\\" and i + 1 < length and text[i + 1] == "'":
					s += "'"
					i += 2
				else:
					s += text[i]
					i += 1
			i += 1
			tokens.append(s)
			continue

		# Preprocessor directive: #...
		if c == "#":
			var s := "#"
			i += 1
			while i < length and text[i] != " " and text[i] != "\t" and text[i] != "\n" and text[i] != "\r" and text[i] != "(" and text[i] != ")":
				s += text[i]
				i += 1
			tokens.append(s)
			continue

		# Variable: $...
		if c == "$":
			var s := "$"
			i += 1
			while i < length and text[i] != " " and text[i] != "\t" and text[i] != "\n" and text[i] != "\r" and text[i] != "(" and text[i] != ")":
				s += text[i]
				i += 1
			tokens.append(s)
			continue

		# Symbol/number: everything else until whitespace or delimiter
		var s := ""
		while i < length:
			var cc := text[i]
			if cc == " " or cc == "\t" or cc == "\n" or cc == "\r" or cc == "(" or cc == ")" or cc == "{" or cc == "}" or cc == "[" or cc == "]" or cc == ";":
				break
			if cc == "/" and i + 1 < length and (text[i + 1] == "/" or text[i + 1] == "*"):
				break
			s += cc
			i += 1
		if s != "":
			tokens.append(s)

	return tokens

# --- Parser: tokens → nested arrays ---
func _parse_tokens(tokens: Array[String]) -> Array:
	var pos := 0
	var result: Array = []
	while pos < tokens.size():
		var parsed := _parse_expr(tokens, pos)
		result.append(parsed[0])
		pos = parsed[1]
	return result

func _parse_expr(tokens: Array[String], pos: int) -> Array:
	if pos >= tokens.size():
		return [null, pos]

	var token: String = tokens[pos]

	if token == "(" or token == "{" or token == "[":
		var list: Array = []
		pos += 1
		var close := ")" if token == "(" else ("}" if token == "{" else "]")
		while pos < tokens.size() and tokens[pos] != close:
			var parsed := _parse_expr(tokens, pos)
			list.append(parsed[0])
			pos = parsed[1]
		if pos < tokens.size():
			pos += 1  # skip closing
		return [list, pos]
	else:
		pos += 1
		return [token, pos]

# --- Metadata extraction ---
func _extract_metadata(tree: Array) -> void:
	# DTA is typically: (songid (name "Title") (artist "Artist") (song (...)) ...)
	# The outermost level may have one or more song entries
	for node in tree:
		if node is Array:
			_extract_song_entry(node)

func _extract_song_entry(node: Array) -> void:
	# node[0] is usually the song shortname
	for i in range(node.size()):
		var item = node[i]
		if not (item is Array) or item.is_empty():
			continue

		var key = item[0]
		if not (key is String):
			continue

		match key:
			"name":
				if item.size() > 1 and song_name == "":
					song_name = _unquote(str(item[1]))
			"artist":
				if item.size() > 1:
					artist = _unquote(str(item[1]))
			"year_released":
				if item.size() > 1:
					year = int(str(item[1]))
			"genre":
				if item.size() > 1:
					genre = str(item[1])
			"vocal_parts":
				if item.size() > 1:
					vocal_parts = int(str(item[1]))
			"song_length":
				if item.size() > 1:
					song_length_ms = int(str(item[1]))
			"preview":
				if item.size() > 2:
					preview_start_ms = int(str(item[1]))
					preview_end_ms = int(str(item[2]))
			"midi_file":
				if item.size() > 1:
					midi_file = _unquote(str(item[1]))
			"rank":
				_parse_ranks(item)
			"song":
				# Nested song block contains tracks, pans, vols, etc.
				_extract_song_entry(item)
			"tracks":
				_parse_tracks(item)
			"pans":
				if item.size() > 1 and item[1] is Array:
					pans.clear()
					for v in item[1]:
						pans.append(float(str(v)))
					total_channels = maxi(total_channels, pans.size())
			"vols":
				if item.size() > 1 and item[1] is Array:
					vols.clear()
					for v in item[1]:
						vols.append(float(str(v)))
					total_channels = maxi(total_channels, vols.size())
			"crowd_channels":
				crowd_channels.clear()
				for j in range(1, item.size()):
					crowd_channels.append(int(str(item[j])))

func _parse_tracks(node: Array) -> void:
	# (tracks ((drum (0 1 2 3)) (bass 6) (guitar (7 8)) ...))
	# or (tracks (name "path") ((drum ...) (bass ...) ...))
	track_channels.clear()
	for item in node:
		if item is Array:
			# Could be the instrument list: ((drum ...) (bass ...) ...)
			if item.size() > 0 and item[0] is Array:
				for inst_entry in item:
					_parse_instrument_entry(inst_entry)
			elif item.size() > 0 and item[0] is String:
				var inst_name: String = item[0]
				if inst_name == "name":
					continue
				_parse_instrument_entry(item)

func _parse_instrument_entry(entry: Array) -> void:
	if entry.is_empty():
		return
	var inst_name := str(entry[0])
	var channels: Array[int] = []
	for i in range(1, entry.size()):
		if entry[i] is Array:
			for ch in entry[i]:
				channels.append(int(str(ch)))
		else:
			var s := str(entry[i])
			if s.is_valid_int():
				channels.append(int(s))
	if channels.size() > 0:
		track_channels[inst_name] = channels
		var max_ch := 0
		for ch in channels:
			max_ch = maxi(max_ch, ch + 1)
		total_channels = maxi(total_channels, max_ch)

func _parse_ranks(node: Array) -> void:
	# (rank (drum 220) (guitar 80) ...)
	for i in range(1, node.size()):
		if node[i] is Array and node[i].size() >= 2:
			var inst: String = str(node[i][0])
			var val: int = int(str(node[i][1]))
			ranks[inst] = val

func _unquote(s: String) -> String:
	if s.begins_with("\"") and s.ends_with("\""):
		return s.substr(1, s.length() - 2)
	return s

# --- Utility ---
func get_available_instruments() -> Array[String]:
	var result: Array[String] = []
	for inst in track_channels:
		result.append(inst)
	return result

func print_summary() -> void:
	print("=== DTA Summary ===")
	print("Song: %s" % song_name)
	print("Artist: %s" % artist)
	print("Year: %d" % year)
	print("Genre: %s" % genre)
	print("Channels: %d" % total_channels)
	print("Tracks: %s" % str(track_channels))
	print("Crowd: %s" % str(crowd_channels))
	print("Ranks: %s" % str(ranks))
