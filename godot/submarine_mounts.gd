extends RefCounted
## Retail hull-relative defaults and player-authored profiles for each model.
const PATH := "res://game_assets/submarine_mounts.json"
# SC equipment callbacks attach to SUB.DFF frame tag 2 (Hull), not the clump
# wrapper. Coordinates below are in the original +Z-forward model space.
# 004449b0, 0047ab70, 004595e0, 004023d0, 0040a920, 00406af0,
# 0047d4a0, 00488230, 00432d50, 0046a930, 004822a0, 0045eca0,
# 00406420, 004209d0, 00489e70, 00452970. Ripper uses its firing origin
# from 00403c80; it has no attached housing frame.
const ORIGINAL := {
	"bubble":Vector3(0,0.22,-0.35), "strobe":Vector3(0,0.255,0.25),
	"deep_sea_lights":Vector3(0,0.16,0.27), "magnet":Vector3(0,-0.2,0),
	"grapple":Vector3(0,-0.23,0), "escape":Vector3(0,-0.3,0),
	"suckomat":Vector3(0,-0.25,-0.1), "missile":Vector3(-0.12,0.15,0),
	"bigears":Vector3(0,0.24,0.22), "depthl":Vector3(0,-0.08,-0.35),
	"attract":Vector3(0,0.22,0.22), "repel":Vector3(0,0.22,0.22),
	"zapper":Vector3(0,0.15,0.18), "flarel":Vector3(-0.12,0.15,0),
	"sflarel":Vector3(-0.12,0.15,0), "rover":Vector3(0,-0.125,-0.35),
	"woosh":Vector3(0,0.25,0.1), "electro":Vector3(0.12,0.18,0.05),
	"ripper":Vector3(0,0.25,0.2),
}
static func is_original(visual: Node3D) -> bool:
	return profile(visual) == "Original:sub.dff"
static func original_pose(visual: Node3D, id: String) -> Transform3D:
	var hull := visual.get_node_or_null("Hull") as Node3D
	var hull_pose := visual.transform * (hull.transform if hull != null else Transform3D.IDENTITY)
	var tilt := deg_to_rad(50.0) if id in ["depthl","rover"] else 0.0
	# Housing wrappers already convert the original model to -Z-forward.
	# Conjugate the source rotation instead of adding another 180-degree yaw.
	return Transform3D(hull_pose.basis * Basis(Vector3.RIGHT,tilt) * Basis(Vector3.UP,PI),hull_pose * ORIGINAL[id])
static func launch_point(mount: Node3D, visual: Node3D, id: String, fallback: Vector3) -> Vector3:
	if not is_original(visual): return mount.to_global(fallback)
	var extra := Vector3(0,0,-0.04) if id == "bigears" else Vector3(0,0,-0.3) if id == "electro" else Vector3.ZERO
	return mount.to_global(extra)
static func profile(visual: Node3D) -> String:
	return str(visual.get_meta("asset_mod","Original")) + ":" + str(visual.get_meta("asset_source","SUB.DFF")).get_file().to_lower()
static func read(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}
static func apply(mount: Node3D, visual: Node3D, id: String, path: String = PATH) -> void:
	if is_original(visual) and ORIGINAL.has(id): mount.transform = original_pose(visual,id)
	mount.set_meta("default_mount",mount.transform)
	var entries: Variant = read(path).get(profile(visual),{})
	if not entries is Dictionary: return
	var values: Variant = entries.get(id,{})
	if not values is Dictionary: return
	var position: Variant = values.get("position",[]); var rotation: Variant = values.get("rotation_degrees",[])
	if not _vector_valid(position) or not _vector_valid(rotation): return
	mount.position = Vector3(position[0],position[1],position[2]) * coordinate_scale(visual)
	mount.rotation_degrees = Vector3(rotation[0],rotation[1],rotation[2])
	var size: Variant = values.get("scale",1.0)
	if (size is float or size is int) and is_finite(float(size)) and float(size) > 0.0:
		mount.scale = Vector3.ONE * float(size)
static func coordinate_scale(visual: Node3D) -> float:
	return 1.25 if profile(visual) == "Original:sub.dff" else 1.0
static func _vector_valid(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	for component in value:
		if not (component is int or component is float) or not is_finite(float(component)): return false
	return true
static func save(visual: Node3D, mounts: Dictionary, path: String = PATH) -> Error:
	var data := read(path); var values := {}
	for id in mounts:
		var mount: Node3D = mounts[id]
		var position: Vector3 = mount.position / coordinate_scale(visual)
		values[id] = {"position":[position.x,position.y,position.z],"rotation_degrees":[mount.rotation_degrees.x,mount.rotation_degrees.y,mount.rotation_degrees.z],"scale":mount.scale.x}
	data[profile(visual)] = values
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data,"\t") + "\n")
	return OK
