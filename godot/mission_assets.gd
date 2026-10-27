extends RefCounted
## Prepare reusable mission assets while the existing startup screen is visible.
const Assets = preload("res://clump_loader.gd")
const Audio = preload("res://legacy_audio.gd")
const MODELS := ["CARAVAN","MINING","MINE","HARDMINE","PRISON","TECHNEW","TECH2SUB","TRAD2","TRAD-SUB","TRADSHUT","TECHSHUT","TRADHERD","TECHHERD","FREIGHT","PIRATE","OUTPOST","TECHPOST","CANISTER","WALKER","WALKHEAD","ESCAPE","TURRET","LITEBEEM","MISSILE","HMISSILE","TMISSILE","DEPTHD","SMALROCK","ROCK","BIGROCK","PIXIE","CHAIN","JELLYEGG","EGGBROKE"]
const ANIMATED := ["SILVER","BADJELLY","LIONFISH","MUTANT","MSILVER","BABY","MEEL","BIGEEL","TESTDOOR","MOMJELLY","KIDJELLY"]

static func prepare(game: Node) -> void:
	var loading: bool = game.world_loading; game.world_loading = true
	var budget := Time.get_ticks_usec()
	for model in MODELS+ANIMATED:
		var path: String = game.game_folder.path_join("CLUMPS/"+model+".DFF")
		if FileAccess.file_exists(path):
			var visual := Assets.load_clump(path,PackedStringArray(),model in ANIMATED)
			if visual != null:
				game.water_visuals.attach(visual); game.natural_light.attach(visual); visual.free()
		if Time.get_ticks_usec()-budget > 4000:
			await game.get_tree().process_frame; budget = Time.get_ticks_usec()
	# Known catalogue paths also work with installations whose directories
	# cannot be enumerated, without depending on unused/local language files.
	var sounds: Array[String] = []
	for code in game.gameplay_catalogue.tables.get("radio_messages",{}).get("records",{}):
		sounds.append(game.game_folder.path_join("WAVES/ENGLISH/"+str(code).to_upper()+".RAW"))
	for code in ["EXPL","EXPLODE1","EXPLODE2","SPLAT","DCHARGE","DEPTH","MISSILE","HMISSILE","ZAPPER"]:
		sounds.append(game.game_folder.path_join("WAVES/"+code+".RAW"))
	for id in preload("res://mod_registry.gd").layers:
		if str(id).begins_with("audio."):
			for entry in preload("res://mod_registry.gd").candidates(id): sounds.append(entry.path)
	for path in sounds:
		if FileAccess.file_exists(path): Audio.load_file(path)
		if Time.get_ticks_usec()-budget > 4000:
			await game.get_tree().process_frame; budget = Time.get_ticks_usec()
	var portraits := {}
	for row in game.gameplay_catalogue.tables.get("radio_messages",{}).get("records",{}).values(): portraits[str(row.get("portrait",""))] = true
	for portrait in portraits:
		preload("res://docking_radio.gd").speaker_portrait(game.game_folder,portrait)
		preload("res://docking_radio.gd").speaker_portrait(game.game_folder,portrait,true)
		if Time.get_ticks_usec()-budget > 4000:
			await game.get_tree().process_frame; budget = Time.get_ticks_usec()
	game.world_loading = loading
