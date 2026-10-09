extends RefCounted

const DEFAULT_ROOT := "res://../Mods"
const MOVEMENT_KEYS := ["main_forward", "main_reverse", "side_thrust", "forward_speed", "reverse_speed", "vertical_speed", "forward_drag", "lateral_drag", "vertical_drag", "turn_acceleration", "turn_speed", "turn_drag", "tilt_speed", "camera_distance", "mass", "water_resistance", "pitch_acceleration", "pitch_speed", "upright_strength", "upright_damping", "propeller_spin_down", "bubble_rate", "impact_damage_threshold", "impact_damage_scale"]
static var initialized := false
static var root := ""
static var preference_path := ""
static var packs: Array[Dictionary] = []
static var enabled: Array[String] = []
static var order: Array[String] = []
static var layers := {}
static var movement := {}
static var conflicts: Array[String] = []
static var runtime_warnings: Array[String] = []

static func ensure(read_preferences: bool = true) -> void:
	if not initialized: initialize(read_preferences)

static func initialize(read_preferences: bool = true, folder: String = DEFAULT_ROOT, preferences: String = "") -> void:
	root = preload("res://runtime_paths.gd").external(folder).replace("\\", "/").simplify_path().trim_suffix("/")
	preference_path = preload("res://player_storage.gd").preferences_path() if preferences.is_empty() else preferences
	enabled.clear()
	order.clear()
	if read_preferences:
		var config := ConfigFile.new()
		if config.load(preference_path) == OK:
			for id in config.get_value("mods", "enabled", []): enabled.append(str(id))
			for id in config.get_value("mods", "order", []): order.append(str(id))
	initialized = true
	refresh()

static func refresh() -> void:
	packs.clear()
	if not DirAccess.dir_exists_absolute(root): _rebuild(); return
	var ids := {}
	for folder in DirAccess.get_directories_at(root):
		if folder.begins_with("."): continue
		var pack := _read_pack(root.path_join(folder))
		if pack.is_empty(): continue
		if ids.has(pack.id):
			pack.valid = false
			pack.errors.append("Duplicate mod ID: " + str(pack.id))
			ids[pack.id].valid = false
			ids[pack.id].errors.append("Duplicate mod ID: " + str(pack.id))
		ids[pack.id] = pack
		packs.append(pack)
	packs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var first := order.find(str(a.id))
		var second := order.find(str(b.id))
		if first < 0: first = 100000
		if second < 0: second = 100000
		return str(a.name).naturalnocasecmp_to(str(b.name)) < 0 if first == second else first < second
	)
	order.clear()
	for pack in packs: order.append(str(pack.id))
	_rebuild()

static func _read_pack(folder: String) -> Dictionary:
	var path := folder.path_join("mod.json")
	if not FileAccess.file_exists(path): return {}
	var pack := {"id": folder.get_file(), "name": folder.get_file(), "version": "", "description": "", "folder": folder, "valid": true, "errors": [], "assets": {}, "movement": {}}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		pack.valid = false
		pack.errors.append("Could not read mod.json: " + parser.get_error_message())
		return pack
	var manifest: Dictionary = parser.data
	if int(manifest.get("schema_version", 0)) != 1:
		pack.valid = false
		pack.errors.append("Unsupported manifest version; expected schema_version 1.")
	var id := str(manifest.get("id", ""))
	var valid_id := not id.is_empty()
	for character in id:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789._-": valid_id = false
	if not valid_id:
		pack.valid = false
		pack.errors.append("Mod ID must contain lowercase letters, numbers, dots, underscores or hyphens.")
	else: pack.id = id
	pack.name = str(manifest.get("name", pack.id))
	pack.version = str(manifest.get("version", "1.0"))
	pack.description = str(manifest.get("description", ""))
	var settings: Variant = manifest.get("movement", {})
	if settings is Dictionary:
		for key in settings:
			var value: Variant = settings[key]
			if key not in MOVEMENT_KEYS or not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0:
				pack.errors.append("Ignored invalid movement setting: " + str(key))
			else: pack.movement[key] = float(value)
	else: pack.errors.append("movement must be an object of setting/value pairs.")
	var assets: Variant = manifest.get("assets", {})
	if not assets is Dictionary:
		pack.errors.append("assets must be an object of asset-ID/replacement pairs.")
		return pack
	for key in assets:
		var asset_id := canonical_id(str(key))
		var entry: Variant = assets[key]
		if entry is String: entry = {"file": entry}
		if not entry is Dictionary:
			pack.errors.append("Invalid asset entry: " + str(key)); continue
		var relative := str(entry.get("file", "")).replace("\\", "/")
		var resolved := folder.path_join(relative).simplify_path()
		if relative.is_empty() or relative.is_absolute_path() or not resolved.begins_with(folder + "/"):
			pack.errors.append("Asset path must stay inside its mod folder: " + str(key)); continue
		var extension := relative.get_extension().to_lower()
		var model := asset_id == "submarine.player" or asset_id.begins_with("model.") or asset_id in ["hud.tilt", "hud.equipment", "hud.map", "hud.weapon", "hud.shield"]
		var texture := asset_id.begins_with("texture.")
		var audio := asset_id in ["audio.submarine.main_propeller", "audio.submarine.side_pods", "audio.submarine.pod_rotation", "audio.submarine.impact_hit1", "audio.submarine.impact_hit3", "audio.submarine.impact_creaking", "audio.docking.sequence", "audio.docking.doors", "audio.docking.door_stop", "audio.weapon.zapper", "audio.creature.death", "audio.object.mine.explosion"]
		var map := asset_id == "map.scen1"
		var gameplay := asset_id in ["data.gameplay", "data.wildlife"]
		var ui := asset_id in ["ui.dock","ui.saves","ui.main","ui.controls"]
		if (not model and not texture and not audio and not map and not gameplay and not ui) or (model and extension not in ["glb", "dff"]) or (texture and extension not in ["png", "jpg", "jpeg", "webp", "bmp", "ras"]) or (audio and extension not in ["wav", "ogg", "mp3", "raw"]) or ((map or gameplay or ui) and extension != "json"):
			pack.errors.append("Unsupported asset ID or file type: " + str(key)); continue
		if not FileAccess.file_exists(resolved):
			pack.errors.append("Missing asset file: " + relative); continue
		var scale: Variant = entry.get("scale", 1.0)
		if not (scale is float or scale is int) or not is_finite(float(scale)) or float(scale) <= 0.0:
			pack.errors.append("Invalid model scale: " + str(key)); continue
		var parts: Variant = entry.get("parts", {})
		if not parts is Dictionary: parts = {}
		var material_textures := {}
		var bindings: Variant = entry.get("material_textures", {})
		if bindings is Dictionary:
			for slot in bindings:
				var texture_id := canonical_id(str(bindings[slot]))
				if not str(slot).is_valid_int() or int(str(slot)) < 0 or not texture_id.begins_with("texture."):
					pack.errors.append("Ignored invalid material texture binding: " + str(slot)); continue
				material_textures[str(slot)] = texture_id
		else: pack.errors.append("material_textures must map GLB material indices to texture IDs.")
		var axis := str(entry.get("forward_axis", "-Z" if extension == "glb" else "+Z"))
		if axis not in ["+Z", "-Z"]:
			pack.errors.append("forward_axis must be +Z or -Z: " + str(key)); continue
		var trigger: Variant = entry.get("trigger_distance","")
		if trigger != "" and (not model or trigger != "model_radius"):
			pack.errors.append("Model trigger_distance must be model_radius: " + str(key)); continue
		pack.assets[asset_id] = {"id": asset_id, "path": resolved, "relative": relative, "pack": pack.id, "name": pack.name, "scale": float(scale), "forward_axis": axis, "parts": parts.duplicate(), "material_textures": material_textures}
		if trigger == "model_radius": pack.assets[asset_id].trigger_distance = trigger
	return pack

static func canonical_id(id: String) -> String:
	id = id.strip_edges().to_lower()
	if id == "audio.submarine.thrust": return "audio.submarine.pod_rotation"
	return "submarine.player" if id == "model.sub" else id

static func model_id(path: String) -> String:
	return canonical_id("model." + path.get_file().get_basename())

static func _rebuild() -> void:
	layers.clear()
	movement.clear()
	conflicts.clear()
	runtime_warnings.clear()
	var movement_sources := {}
	for pack in packs:
		if not pack.valid or str(pack.id) not in enabled: continue
		for id in pack.assets:
			if layers.has(id): conflicts.append("%s: %s overrides %s" % [id, pack.name, layers[id][-1].name])
			else: layers[id] = []
			layers[id].append(pack.assets[id])
		for key in pack.movement:
			if movement_sources.has(key): conflicts.append("Movement %s: %s overrides %s" % [key, pack.name, movement_sources[key]])
			movement[key] = pack.movement[key]
			movement_sources[key] = pack.name

static func candidates(id: String) -> Array:
	var result: Array = layers.get(canonical_id(id), []).duplicate()
	result.reverse()
	return result

static func note(message: String) -> void:
	if message not in runtime_warnings: runtime_warnings.append(message)

static func apply(ids: Array[String], priorities: Array[String], persist: bool = true) -> Error:
	if persist:
		var directory_result := preload("res://player_storage.gd").ensure_parent(preference_path)
		if directory_result != OK: return directory_result
		var config := ConfigFile.new(); config.load(preference_path)
		config.set_value("mods", "enabled", ids)
		config.set_value("mods", "order", priorities)
		var result := config.save(preference_path)
		if result != OK: return result
	enabled = ids.duplicate()
	order = priorities.duplicate()
	refresh()
	return OK

static func active_ids() -> Array[String]:
	var result: Array[String] = []
	for pack in packs:
		if pack.valid and str(pack.id) in enabled: result.append(str(pack.id))
	return result

static func movement_profile() -> String:
	var ids := active_ids()
	if ids.is_empty(): return "user://submarine_tuning.cfg"
	return "user://movement-mod-%s.cfg" % JSON.stringify(ids).sha256_text().substr(0, 16)
