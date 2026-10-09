extends RefCounted
## Save-safe identities, independent of Godot instance IDs and model/type names.

static func authored(group_id: String, index: int) -> String:
	var group := group_id.uri_encode()
	if group.length() > 180: group = "sha256:" + group_id.sha256_text()
	return "authored/%s/%d" % [group,index]

static func generated() -> String:
	return "spawn/" + Crypto.new().generate_random_bytes(16).hex_encode()

static func valid(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 256 and value == value.strip_edges()

static func assign_id(entity: Node, identity: String = "") -> String:
	if identity.is_empty(): identity = generated()
	entity.set_meta("entity_id",identity)
	return identity

static func of(entity: Node) -> String:
	var identity: Variant = entity.get_meta("entity_id","")
	return str(identity) if valid(identity) else assign_id(entity)
