extends Node

# Aquatraz's city handler 0x44c610 rotates its clump about Y by one
# degree per normalized tick; 0x48d360 supplies 25 ticks per second.
const SPEED := deg_to_rad(25.0)
var angle := 0.0
var rest_poses := {}
var loading_root: Node

func _ready() -> void:
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor.has_meta("bounds"):
			loading_root = ancestor; break
		ancestor = ancestor.get_parent()

func _physics_process(delta: float) -> void:
	# Build derived world data against the authored pose before simulation starts.
	if is_instance_valid(loading_root) and loading_root.get_meta("world_loading", false): return
	angle = fposmod(angle + SPEED * delta,TAU)
	var spin := Transform3D(Basis(Vector3.UP,angle),Vector3.ZERO)
	# Keep the authored placement and docking collision path unchanged.
	# Include collision added after model loading, and modern mod meshes.
	for child in get_parent().get_children():
		if not child is Node3D: continue
		if not rest_poses.has(child): rest_poses[child] = child.transform
		child.transform = spin * rest_poses[child]
