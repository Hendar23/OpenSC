extends RefCounted
## Shared definitions for authored machines and emitters. Placements own only
## their transform, affiliation and operating area; tuning belongs to a type.
const Turret = preload("res://gun_turret.gd")
const Pirate = preload("res://pirate_submarine.gd")
const Trader = preload("res://trader_submarine.gd")
const Vehicle = preload("res://ground_vehicle.gd")
const Patrol = preload("res://patrol_submarine.gd")
const Bubbles = preload("res://bubble_stream.gd")
const Smoke = preload("res://smoke_emitter.gd")

static func family(entry: Dictionary) -> String:
	if entry.get("kind") in ["smoke","bubbles"]: return str(entry.kind)
	if entry.get("family") == "patrol" and entry.get("model") in Patrol.PATROL_MODELS: return "patrol"
	if entry.get("model") in ["PRISON","TRAD2","TECH2SUB"]: return "patrol"
	if entry.get("kind") != "model": return ""
	if entry.get("model") == "TURRET": return "turret"
	if entry.get("model") in Pirate.PIRATE_MODELS: return "pirate"
	if entry.get("model") in Trader.MODELS: return "trader"
	if entry.get("model") in Vehicle.MODELS: return "vehicle"
	return ""

static func collection(kind: String) -> String:
	return "npc_types" if kind in ["vehicle","trader","pirate","patrol"] else "entity_types"

static func reference_key(kind: String) -> String:
	return "npc_type" if kind in ["vehicle","trader","pirate","patrol"] else "entity_type"

static func defaults(kind: String, model: String = "") -> Dictionary:
	var result: Dictionary = Patrol.PATROL_DEFAULTS.duplicate() if kind == "patrol" else Bubbles.DEFAULTS.duplicate() if kind == "bubbles" else Smoke.DEFAULTS.duplicate() if kind == "smoke" else (Turret.DEFAULTS.duplicate() if kind == "turret" else Pirate.PIRATE_DEFAULTS.duplicate() if kind == "pirate" else Trader.DEFAULTS.duplicate() if kind == "trader" else Vehicle.DEFAULTS.duplicate())
	for local in ["turret_armed","turret_faction","npc_radius","npc_faction"]: result.erase(local)
	if kind == "patrol": result.npc_armed = model in ["TRAD2","TECH2SUB"]
	if kind == "vehicle" and model == "TECHTRUK": result.npc_speed = 0.3
	return result

static func find_type(data: Dictionary, ref: String, id: String) -> Dictionary:
	for item in data.get("npc_types" if ref == "npc_type" else "entity_types",[]):
		if item.id == id: return item
	return {}

static func effective(data: Dictionary, entry: Dictionary) -> Dictionary:
	var result := entry.duplicate(true)
	for ref in ["entity_type","npc_type"]:
		if not entry.has(ref): continue
		var type := find_type(data,ref,str(entry[ref]))
		result.family = type.get("family","")
		for key in type:
			if key not in ["id","name","family"]: result[key] = type[key]
	return result

static func normalized(values: Dictionary) -> Dictionary:
	# JSON parses numbers as floats; dictionary equality distinguishes int/float.
	# Numeric representation must not turn identical tuning into extra variants.
	var result := values.duplicate(true)
	for key in result:
		if result[key] is int or result[key] is float: result[key] = float(result[key])
	return result

static func migrate(data: Dictionary) -> void:
	for list in ["entity_types","npc_types"]:
		if not data.has(list): data[list] = []
	for entry in data.get("entities",{}).values():
		# Tombstones must not recreate a template after its last instance and the
		# template itself have been removed in the editor.
		if entry.get("deleted",false): continue
		var kind := family(entry)
		if kind.is_empty() or entry.has(reference_key(kind)): continue
		var values := defaults(kind,str(entry.get("model","")))
		for key in values: values[key] = entry.get(key,values[key])
		values.kind = kind if kind in ["smoke","bubbles"] else "model"
		values.model = str(entry.get("model",""))
		var list: Array = data[collection(kind)]
		var match_id := ""
		for type in list:
			var compare: Dictionary = type.duplicate(true)
			for key in ["id","name","family"]: compare.erase(key)
			if normalized(compare) == normalized(values): match_id = type.id; break
		if match_id.is_empty():
			var stem := kind + ("_truck" if values.model == "TECHTRUK" else "_car" if kind in ["vehicle","trader","pirate","patrol"] else "_homing" if values.get("turret_homing",false) else "")
			match_id = stem
			var suffix := 2
			while list.any(func(type: Dictionary) -> bool: return type.id == match_id):
				match_id = stem + "_" + str(suffix); suffix += 1
			var title := "Bubble stream" if kind == "bubbles" else "Patrol vessel" if kind == "patrol" else "Smoke emitter" if kind == "smoke" else ("Homing gun turret" if values.get("turret_homing",false) else "Gun turret")
			if kind == "pirate": title = "Pirate submarine"
			if kind == "trader": title = "Bohine shuttle" if values.model == "TRADSHUT" else "Procha shuttle"
			if kind == "vehicle": title = "Trader car" if values.model == "TRADCAR" else "Tech truck"
			values = values.duplicate(true)
			values.merge({"id":match_id,"name":title + (" (variant %d)" % (suffix - 1) if suffix > 2 else ""),"family":kind})
			list.append(values)
		entry[reference_key(kind)] = match_id
		for key in defaults(kind): entry.erase(key)

static func valid(data: Dictionary) -> bool:
	for list_name in ["entity_types","npc_types"]:
		var list: Variant = data.get(list_name,[])
		if not list is Array or list.size() > 256: return false
		var ids := {}
		for type in list:
			if not type is Dictionary or not type.get("id") is String or type.id.is_empty() or ids.has(type.id) or not type.get("name") is String: return false
			ids[type.id] = true
			var kind := str(type.get("family",""))
			if kind not in (["vehicle","trader","pirate","patrol"] if list_name == "npc_types" else ["turret","smoke","bubbles"]) or family(type) != kind: return false
			var allowed := defaults(kind).keys() + ["id","name","family","kind","model"]
			for key in type:
				if key not in allowed: return false
	for entry in data.get("entities",{}).values():
		if not entry is Dictionary: return false
		for ref in ["entity_type","npc_type"]:
			if not entry.has(ref): continue
			if not entry[ref] is String: return false
			var type := find_type(data,ref,entry[ref])
			if type.is_empty() or entry.get("kind") != type.kind: return false
			if entry.has("entity_type") and entry.has("npc_type"): return false
			# Shared properties may not silently override the template.
			for key in defaults(type.family):
				if entry.has(key): return false
	return true
