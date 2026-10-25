extends RefCounted
## The entrance is shared; internal berths never hold a reservation.
static func owner(port: Dictionary) -> Node:
	if port.is_empty() or not is_instance_valid(port.get("node")) or not port.node.has_meta("dock_owner"): return null
	var value: Variant = port.node.get_meta("dock_owner",null)
	return value.get_ref() if value is WeakRef else null

static func disabled(port: Dictionary) -> bool:
	return not port.is_empty() and is_instance_valid(port.get("node")) and bool(port.node.get_meta("mission_dock_disabled",false))

static func acquire(port: Dictionary, actor: Node) -> bool:
	if disabled(port): return false
	var existing := owner(port)
	if existing != null and existing != actor: return false
	port.node.set_meta("dock_owner",weakref(actor)); return true

static func release(port: Dictionary, actor: Node) -> void:
	if owner(port) == actor: port.node.remove_meta("dock_owner")

static func open(port: Dictionary, amount: float) -> void:
	for instance in port.meshes:
		var count: int = instance.mesh.get_blend_shape_count() + 1
		var phase := clampf(amount,0,1) * (count - 1)
		var first := int(floor(phase)); var next := mini(first + 1,count - 1)
		var weight := phase - first
		for pose in range(1,count):
			instance.set_blend_shape_value(pose - 1,(1.0 - weight if pose == first else 0.0) + (weight if pose == next else 0.0))
