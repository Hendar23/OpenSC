extends RefCounted
const VERSION := 1
const SLOT_COUNT := 7
const MAX_FILE_BYTES := 16000000
var folder := preload("res://player_storage.gd").saves_path()
var error := ""
var city_names := {}
func path(slot: int) -> String:
	return folder.path_join("before-mission.json" if slot == -1 else "slot-%d.json" % slot)
func read(slot: int) -> Dictionary:
	error = ""
	if slot < -1 or slot >= SLOT_COUNT: error = "Invalid save slot."; return {}
	var file := FileAccess.open(path(slot),FileAccess.READ)
	if file == null: error = "No saved game in this slot."; return {}
	if file.get_length() > MAX_FILE_BYTES: error = "Save file is too large."; return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK: error = "This save is damaged."; return {}
	var data: Variant = parser.data
	if not valid(data): error = "This save is damaged or uses an unsupported version."; return {}
	return data
static func valid(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != VERSION: return false
	if data.get("progress") is Dictionary and data.progress.has("missions") and not preload("res://mission_state.gd").valid(data.progress.missions): return false
	if not data.get("dock") is Dictionary or not data.dock.get("id") is float and not data.dock.get("id") is int: return false
	var dock_id := float(data.dock.id)
	if not is_finite(dock_id) or dock_id < 0 or dock_id != floorf(dock_id): return false
	if not data.get("name") is String or not data.get("saved_at") is String or not data.get("map_signature") is String: return false
	if not preload("res://map_document.gd").finite_array(data.get("pose"),12): return false
	if absf(preload("res://map_document.gd").decode(data.pose).basis.determinant()) < 0.00001: return false
	var hour: Variant = data.get("hour")
	if not (hour is float or hour is int) or not is_finite(float(hour)) or float(hour) < 0 or float(hour) >= 24: return false
	if not data.get("equipment") is Array or data.equipment.size() > 64 or not data.get("weapons") is Array or data.weapons.size() > 64: return false
	var equipment_ids := {}
	for item in data.equipment:
		if not item is Dictionary or not item.get("id") is String or not item.get("enabled") is bool: return false
		if item.id.is_empty() or equipment_ids.has(item.id): return false
		equipment_ids[item.id] = true
	var weapon_ids := {}
	for id in data.weapons:
		if not id is String or id.is_empty() or weapon_ids.has(id): return false
		weapon_ids[id] = true
	if not data.get("explored") is String: return false
	if not data.get("discovered_cities",[]) is Array or data.get("discovered_cities",[]).size() > 256: return false
	for id in data.get("discovered_cities",[]):
		if not id is String or id.length() > 128: return false
	if not data.get("equipment_selected","") is String or not data.get("weapon_selected","") is String: return false
	if data.has("objects") and not preload("res://object_population.gd").valid_snapshot(data.objects): return false
	if data.has("mines") and not preload("res://mine_population.gd").valid_snapshot(data.mines): return false
	if data.has("turrets") and not preload("res://turret_system.gd").valid_snapshot(data.turrets): return false
	if data.has("submarine_traffic") and not preload("res://submarine_traffic.gd").valid_snapshot(data.submarine_traffic): return false
	if data.has("ground_traffic") and not preload("res://ground_traffic.gd").valid_snapshot(data.ground_traffic): return false
	var bytes := Marshalls.base64_to_raw(data.explored)
	return bytes.size() == preload("res://hud_map.gd").RESOLUTION * preload("res://hud_map.gd").RESOLUTION
func write(slot: int, snapshot: Dictionary) -> Error:
	error = ""
	if slot < -1 or slot >= SLOT_COUNT or not valid(snapshot): error = "Cannot save invalid game state."; return ERR_INVALID_DATA
	if not snapshot.get("progress",{}).get("missions",{}).get("active",{}).is_empty():
		error = "Saving is unavailable during an active mission."; return ERR_UNAVAILABLE
	var serialized := JSON.stringify(snapshot)
	if serialized.to_utf8_buffer().size() > MAX_FILE_BYTES: error = "Save file is too large."; return ERR_INVALID_DATA
	var absolute := ProjectSettings.globalize_path(folder)
	var result := DirAccess.make_dir_recursive_absolute(absolute)
	if result != OK: error = "Cannot create the save folder."; return result
	var target := ProjectSettings.globalize_path(path(slot))
	var file := FileAccess.open(target + ".tmp",FileAccess.WRITE)
	if file == null: error = "Cannot write the save file."; return FileAccess.get_open_error()
	file.store_string(serialized); file.flush()
	result = file.get_error(); file.close()
	if result == OK: result = DirAccess.rename_absolute(target + ".tmp",target)
	if result != OK: error = "Could not finish saving: " + error_string(result)
	return result
func slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in range(SLOT_COUNT):
		var data := read(slot)
		var dock: Dictionary = data.get("dock",{})
		var city := str(city_names.get(int(dock.get("id",-1)),dock.get("name","")))
		result.append({"slot":slot,"exists":FileAccess.file_exists(path(slot)),"valid":not data.is_empty(),"name":data.get("name","Empty slot"),"city":city,"saved_at":data.get("saved_at",""),"error":error})
	return result

func automatic_slot() -> Dictionary:
	var data := read(-1)
	return {"slot":-1,"name":"Auto Save","exists":FileAccess.file_exists(path(-1)),"valid":not data.is_empty(),"city":str(data.get("dock",{}).get("name","")),"saved_at":data.get("saved_at",""),"error":error}
