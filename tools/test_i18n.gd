extends SceneTree


func _initialize() -> void:
	var tr_keys: Array = I18n.STRINGS["tr"].keys()
	var en_keys: Array = I18n.STRINGS["en"].keys()
	tr_keys.sort()
	en_keys.sort()
	assert(tr_keys == en_keys)

	var previous_language := Settings.language
	Settings.language = "en"
	assert(I18n.instrument_name("guitar") == "Guitar")
	assert(I18n.instrument_name("bass") == "Bass")
	assert(I18n.instrument_name("keys") == "Keys")
	assert(I18n.instrument_name("drums") == "Drums")
	assert(I18n.instrument_name("vocals") == "Vocals")
	assert(I18n.decode_stage("decode|drums.ogg|1|3") == "Decoding: drums.ogg (1/3)")
	assert(I18n.decode_stage("normalize") == "Normalizing audio…")
	assert(I18n.decode_stage("write_wav") == "Preparing audio file…")
	assert(I18n.decode_stage("complete") == "Complete")

	var turkish_letters := ["ş", "Ş", "ı", "İ", "ğ", "Ğ", "ç", "Ç", "ö", "Ö", "ü", "Ü"]
	for key in en_keys:
		var value := String(I18n.STRINGS["en"][key])
		for letter in turkish_letters:
			assert(not value.contains(letter), "English key contains Turkish text: %s" % key)

	Settings.language = previous_language
	print("I18n tests passed: key parity, English instruments and progress labels")
	quit(0)
