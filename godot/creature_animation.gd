extends RefCounted
const Morph = preload("res://morph_animation.gd")
var meshes: Array[MeshInstance3D] = []
var parts: Array[Dictionary] = []
func _init(visual: Node3D) -> void:
	Morph.collect(visual, meshes)
	# TURTLE.DFF has six rigid frames and one pose per mesh. These are a
	# procedural swim cycle using the supplied pivots, not recovered keyframes.
	var source: String = visual.get_meta("asset_source", "")
	if source.get_file().to_upper() != "TURTLE.DFF": return
	var body := visual.get_node_or_null("Frame_0")
	if body == null: return
	for item in [["Frame_4", Vector3.BACK, 18.0, 1.0, 0.0], ["Frame_5", Vector3.BACK, 18.0, -1.0, 0.0], ["Frame_2", Vector3.BACK, 8.0, 1.0, PI / 3.0], ["Frame_3", Vector3.BACK, 8.0, -1.0, PI / 3.0], ["Frame_1", Vector3.RIGHT, 2.0, 1.0, PI / 2.0]]:
		var node := body.get_node_or_null(NodePath(item[0])) as Node3D
		if node != null: parts.append({"node": node, "rest": node.basis, "axis": item[1], "amplitude": deg_to_rad(item[2]) * item[3], "phase": item[4]})
func has_animation() -> bool: return not meshes.is_empty() or not parts.is_empty()
func apply(time: float) -> void:
	Morph.apply(meshes, time)
	for part in parts:
		part.node.basis = part.rest * Basis(part.axis, sin(time * TAU * 0.75 + part.phase) * part.amplitude)
