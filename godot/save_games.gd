extends RefCounted
const VERSION := 1
const SLOT_COUNT := 7
var folder := "user://saves"
var error := ""
var city_names := {}
func path(slot: int) -> String:
	return folder.path_join("slot-%d.json" % slot)
func read(slot: int) -> Dictionary:
	error = ""
	if slot < 0 or slot >= SLOT_COUNT: error = "Invalid save slot."; return {}
	var file := FileAccess.open(path(slot),FileAccess.READ)
	if file == null: error = "No saved game in this slot."; return {}
	if file.get_length() > 16000000: error = "Save file is too large."; return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK: error = "This save is damaged."; return {}
	var data: Variant = parser.data
	if not valid(data): error = "This save is damaged or uses an unsupported version."; return {}
	return data
static func valid(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != VERSION: return false
	if not data.get("dock") is Dictionary or not data.dock.get("id") is float and not data.dock.get("id") is int: return false
	if not data.get("name") is String or not data.get("saved_at") is String or not data.get("map_signature") is String: return false
	if not preload("res://map_document.gd").finite_array(data.get("pose"),12): return false
	var hour: Variant = data.get("hour")
	if not (hour is float or hour is int) or not is_finite(float(hour)) or float(hour) < 0 or float(hour) >= 24: return false
	if not data.get("equipment") is Array or data.equipment.size() > 64 or not data.get("weapons") is Array or data.weapons.size() > 64: return false
	for item in data.equipment:
		if not item is Dictionary or not item.get("id") is String or not item.get("enabled") is bool: return false
	for id in data.weapons:
		if not id is String: return false
	if not data.get("explored") is String: return false
	if not data.get("equipment_selected","") is String or not data.get("weapon_selected","") is String: return false
	if data.has("objects") and not preload("res://object_population.gd").valid_snapshot(data.objects): return false
	var bytes := Marshalls.base64_to_raw(data.explored)
	return bytes.size() == preload("res://hud_map.gd").RESOLUTION * preload("res://hud_map.gd").RESOLUTION
func write(slot: int, snapshot: Dictionary) -> Error:
	error = ""
	if slot < 0 or slot >= SLOT_COUNT or not valid(snapshot): error = "Cannot save invalid game state."; return ERR_INVALID_DATA
	var absolute := ProjectSettings.globalize_path(folder)
	var result := DirAccess.make_dir_recursive_absolute(absolute)
	if result != OK: error = "Cannot create the save folder."; return result
	var target := ProjectSettings.globalize_path(path(slot))
	var file := FileAccess.open(target + ".tmp",FileAccess.WRITE)
	if file == null: error = "Cannot write the save file."; return FileAccess.get_open_error()
	file.store_string(JSON.stringify(snapshot)); file.flush()
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
