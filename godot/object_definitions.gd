extends RefCounted
## Shared type stats; placement/count/scatter belong only to object groups.
const FLOATING_MINE := {"id":"floating_mine","name":"Floating Mine","appearance":"sprite","texture":"MINE","mask":"MINEM","model":"MINE","size":1.0,"health":0.5,"damage":30.0,"explosion_radius":2.0,"trigger_distance":0.75,"blast_force":300.0}
static func ensure(data: Dictionary) -> void:
	if not data.has("object_types"): data.object_types = [FLOATING_MINE.duplicate(true)]
	if not data.has("object_groups"): data.object_groups = []
	for entry in data.object_types:
		if not entry.has("blast_force"): entry.blast_force = FLOATING_MINE.blast_force
static func numeric(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum
static func asset(value: Variant) -> bool:
	if not value is String or value.is_empty(): return false
	return not (value.contains("/") or value.contains("\\") or value.contains("..") or value.contains(":"))
static func valid(data: Dictionary) -> bool:
	var types: Variant = data.get("object_types",[FLOATING_MINE])
	var groups: Variant = data.get("object_groups",[])
	if not types is Array or not groups is Array or types.size() > 256 or groups.size() > 256: return false
	var ids := {}
	for entry in types:
		if not entry is Dictionary or not asset(entry.get("id")) or ids.has(entry.id) or not entry.get("name") is String: return false
		ids[entry.id] = true
		if entry.get("appearance") not in ["sprite","model"]: return false
		for key in ["texture","mask","model"]:
			if not asset(entry.get(key)): return false
		for key in ["size","health","damage","explosion_radius","trigger_distance"]:
			if not numeric(entry.get(key),0.01 if key in ["size","health"] else 0.0,100000.0 if key in ["health","damage"] else 1000.0): return false
		if not numeric(entry.get("blast_force",300.0),0,100000): return false
		if entry.has("count") or entry.has("count_min") or entry.has("count_max") or entry.has("radius"): return false
	var group_ids := {}
	var total := 0
	for group in groups:
		if not group is Dictionary or not asset(group.get("id")) or group_ids.has(group.id) or not ids.has(group.get("type")): return false
		group_ids[group.id] = true
		if not group.get("name") is String or not group.get("position") is Array or group.position.size() != 3: return false
		for coordinate in group.position:
			if not numeric(coordinate,-50000,50000): return false
		if not numeric(group.get("count"),1,100) or float(group.count) != floorf(float(group.count)) or not numeric(group.get("radius"),0,1000): return false
		total += int(group.count)
	return total <= 5000
