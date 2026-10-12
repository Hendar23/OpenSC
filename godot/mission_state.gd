extends RefCounted
## Save boundary for the upcoming mission runtime. No objectives run here.
const VERSION := 1
static func empty() -> Dictionary:
	return {"version":VERSION,"active":{},"completed":{}}

static func valid(value: Variant) -> bool:
	return value is Dictionary and value.get("version") == VERSION and value.get("active") is Dictionary and value.get("completed") is Dictionary and _json_value(value,0)

static func _json_value(value: Variant, depth: int) -> bool:
	if depth > 12: return false
	if value is Dictionary:
		if value.size() > 1024: return false
		for key in value:
			if not key is String or key.length() > 256 or not _json_value(value[key],depth + 1): return false
		return true
	if value is Array:
		if value.size() > 1024: return false
		for item in value:
			if not _json_value(item,depth + 1): return false
		return true
	if value is float: return is_finite(value)
	if value is String: return value.length() <= 4096
	return value == null or value is bool or value is int

static func restore(value: Variant) -> Dictionary:
	return value.duplicate(true) if valid(value) else empty()
