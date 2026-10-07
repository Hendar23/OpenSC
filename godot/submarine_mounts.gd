extends RefCounted
## Player-authored mounting profiles, separate for each submarine replacement.
const PATH := "res://game_assets/submarine_mounts.json"
static func profile(visual: Node3D) -> String:
	return str(visual.get_meta("asset_mod","Original")) + ":" + str(visual.get_meta("asset_source","SUB.DFF")).get_file().to_lower()
static func read(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}
static func apply(mount: Node3D, visual: Node3D, id: String, path: String = PATH) -> void:
	mount.set_meta("default_mount",mount.transform)
	var entries: Variant = read(path).get(profile(visual),{})
	if not entries is Dictionary: return
	var values: Variant = entries.get(id,{})
	if not values is Dictionary: return
	var position: Variant = values.get("position",[]); var rotation: Variant = values.get("rotation_degrees",[])
	if not _vector_valid(position) or not _vector_valid(rotation): return
	mount.position = Vector3(position[0],position[1],position[2])
	mount.rotation_degrees = Vector3(rotation[0],rotation[1],rotation[2])
	var size: Variant = values.get("scale",1.0)
	if (size is float or size is int) and is_finite(float(size)) and float(size) > 0.0:
		mount.scale = Vector3.ONE * float(size)
static func _vector_valid(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	for component in value:
		if not (component is int or component is float) or not is_finite(float(component)): return false
	return true
static func save(visual: Node3D, mounts: Dictionary, path: String = PATH) -> Error:
	var data := read(path); var values := {}
	for id in mounts:
		var mount: Node3D = mounts[id]
		values[id] = {"position":[mount.position.x,mount.position.y,mount.position.z],"rotation_degrees":[mount.rotation_degrees.x,mount.rotation_degrees.y,mount.rotation_degrees.z],"scale":mount.scale.x}
	data[profile(visual)] = values
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data,"\t") + "\n")
	return OK
