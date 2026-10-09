extends RefCounted
## Shared type stats; placement/count/scatter belong only to object groups.
const FLOATING_MINE := {"id":"floating_mine","name":"Floating Mine","appearance":"sprite","texture":"MINE","mask":"MINEM","model":"MINE","size":1.0,"health":0.5,"damage":30.0,"explosion_radius":2.0,"trigger_distance":0.75,"blast_force":300.0}
const THORIUM := {"id":"thorium","name":"Thorium","behavior":"thorium","appearance":"model","texture":"THORIUM","mask":"THORIUM","model":"THORIUM","size":1.0,"health":1.0,"damage":0.0,"explosion_radius":0.0,"trigger_distance":0.0,"blast_force":0.0,"mass":2.0,"shard_mass":1.0,"shard_scale_percent":100.0,"shard1":"SHARD1","shard2":"SHARD2","shard3":"SHARD3","radiation_range":1.5,"radiation_strength":5.0,"glow_energy":1.0,"glow_range":3.0,"glow_emission":0.25,"glow_red":1.0,"glow_green":0.8,"glow_blue":0.1,"spawn_chance":10.0,"maximum_population":60}
const SALVAGE := {"id":"bottletop","name":"Bottletop","behavior":"salvage","appearance":"model","texture":"BOTTLTOP","mask":"BOTTLTOP","model":"BOTTLTOP","size":1.0,"health":1.0,"damage":0.0,"explosion_radius":0.0,"trigger_distance":0.0,"blast_force":0.0,"mass":2.0,"magnet_compatible":true,"spawn_chance":100.0,"maximum_population":20}
const CIGARETTE := {"id":"cigarette_end","name":"Cigarette End","behavior":"salvage","appearance":"model","texture":"FAGBUTT","mask":"FAGBUTT","model":"FAGBUTT","size":1.0,"health":1.0,"damage":0.0,"explosion_radius":0.0,"trigger_distance":0.0,"blast_force":0.0,"mass":0.6,"magnet_compatible":false,"grapple_compatible":true,"delivery_commodity":"tobacco","delivery_quantity":1,"spawn_chance":100.0,"maximum_population":20}
const CLAM := {"id":"clam","name":"Clam","behavior":"clam","appearance":"model","texture":"CLAM","mask":"CLAM","model":"CLAM","size":1.0,"health":1.0,"damage":0.0,"explosion_radius":0.0,"trigger_distance":0.0,"blast_force":0.0,"magnet_compatible":false,"grapple_compatible":false,"pearl_type":"pearl","pearl_height":0.2,"close_distance":0.75,"open_angle":90.0,"closed_angle":10.0,"opening_speed":75.0,"closing_speed":750.0,"regrowth_seconds":7200.0,"release_distance":1.0}
const PEARL := {"id":"pearl","name":"Pearl","behavior":"pearl","appearance":"model","texture":"PEARL","mask":"PEARL","model":"PEARL","size":0.143715,"health":1.0,"damage":0.0,"explosion_radius":0.0,"trigger_distance":0.0,"blast_force":0.0,"mass":1.0,"magnet_compatible":false,"grapple_compatible":false,"pickup_commodity":"pearls"}
static func metal_types() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in [["bottletop","Bottletop","BOTTLTOP",2.0],["milktop","Milktop","MILKTOP",1.0],["coin","Coin","COIN",1.5]]:
		var definition := SALVAGE.duplicate(true)
		definition.id = item[0]; definition.name = item[1]; definition.model = item[2]; definition.texture = item[2]; definition.mask = item[2]; definition.mass = item[3]
		result.append(definition)
	return result
static func inert_thorium(base: Dictionary = THORIUM) -> Dictionary:
	var definition := base.duplicate(true)
	definition.id = "inert_thorium"; definition.name = "Inert Thorium"
	# Original INERTTHORIUM differs only in its radiation inflict value (1/10).
	definition.radiation_strength = float(base.get("radiation_strength",THORIUM.radiation_strength)) * 0.1
	# Later replenishment for this type has not been recovered; authored placement
	# and the existing editable random-drop settings remain independent.
	definition.spawn_chance = 0.0
	return definition
static func ensure(data: Dictionary) -> void:
	if not data.has("object_types"): data.object_types = [FLOATING_MINE.duplicate(true)]
	if not data.has("object_groups"): data.object_groups = []
	if not data.object_types.any(func(entry: Dictionary) -> bool: return entry.get("id","") == "thorium"):
		data.object_types.append(THORIUM.duplicate(true))
	if not data.object_types.any(func(entry: Dictionary) -> bool: return entry.get("id","") == "inert_thorium"):
		data.object_types.append(inert_thorium(data.object_types.filter(func(entry: Dictionary) -> bool: return entry.get("id","") == "thorium")[0]))
	for definition in metal_types() + [CIGARETTE,CLAM,PEARL]:
		if not data.object_types.any(func(entry: Dictionary) -> bool: return entry.get("id","") == definition.id): data.object_types.append(definition.duplicate(true))
	for entry in data.object_types:
		var delivery := delivery_defaults(entry)
		if not entry.has("delivery_commodity"): entry.delivery_commodity = delivery.commodity
		if not entry.has("delivery_quantity"): entry.delivery_quantity = delivery.quantity
		if not entry.has("behavior"): entry.behavior = "mine"
		if not entry.has("magnet_compatible"): entry.magnet_compatible = entry.behavior == "salvage" and entry.get("id","") != "cigarette_end"
		if not entry.has("grapple_compatible"): entry.grapple_compatible = entry.behavior == "thorium" or entry.get("id","") == "cigarette_end"
		if entry.behavior == "thorium":
			for key in THORIUM:
				if not entry.has(key): entry[key] = THORIUM[key]
			entry.erase("shard_size")
		if entry.behavior == "salvage":
			for key in SALVAGE:
				if not entry.has(key): entry[key] = SALVAGE[key]
		if entry.behavior in ["clam","pearl"]:
			for key in (CLAM if entry.behavior == "clam" else PEARL):
				if not entry.has(key): entry[key] = (CLAM if entry.behavior == "clam" else PEARL)[key]
		if not entry.has("blast_force"): entry.blast_force = FLOATING_MINE.blast_force
static func numeric(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum
static func delivery_defaults(entry: Dictionary) -> Dictionary:
	if entry.get("id","") == "cigarette_end": return {"commodity":"tobacco","quantity":1}
	if entry.get("behavior","") == "thorium" or entry.get("id","") == "thorium": return {"commodity":"ore","quantity":4}
	if entry.get("id","") == "coin": return {"commodity":"copper","quantity":2}
	if entry.get("behavior","") == "salvage" or entry.get("id","") in ["bottletop","milktop"]: return {"commodity":"metal","quantity":2}
	return {"commodity":"","quantity":0}
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
		if entry.has("delivery_commodity") and (not entry.delivery_commodity is String or (not entry.delivery_commodity.is_empty() and not asset(entry.delivery_commodity))): return false
		if entry.has("delivery_quantity") and (not numeric(entry.delivery_quantity,0,999999) or float(entry.delivery_quantity) != floorf(float(entry.delivery_quantity))): return false
		for flag in ["magnet_compatible","grapple_compatible"]:
			if entry.has(flag) and not entry[flag] is bool: return false
		if entry.get("behavior","mine") not in ["mine","thorium","salvage","clam","pearl"]: return false
		if entry.get("behavior","mine") == "thorium":
			for key in ["mass","shard_mass"]:
				if not numeric(entry.get(key,THORIUM[key]),0.01,1000): return false
			for key in ["radiation_range","radiation_strength","glow_energy","glow_range","glow_emission","glow_red","glow_green","glow_blue"]:
				if not numeric(entry.get(key,THORIUM[key]),0,1.0 if key in ["glow_red","glow_green","glow_blue"] else 1000.0): return false
			if not numeric(entry.get("shard_scale_percent",100.0),0.1,1000): return false
			for key in ["shard1","shard2","shard3"]:
				if not asset(entry.get(key,THORIUM[key])): return false
			if not numeric(entry.get("spawn_chance",0),0,100): return false
			if not numeric(entry.get("maximum_population",60),0,5000) or float(entry.get("maximum_population",60)) != floorf(float(entry.get("maximum_population",60))): return false
		if entry.get("behavior","mine") == "salvage":
			if not numeric(entry.get("mass",2.0),0.01,1000) or not numeric(entry.get("spawn_chance",0),0,100): return false
			if not numeric(entry.get("maximum_population",20),0,5000) or float(entry.get("maximum_population",20)) != floorf(float(entry.get("maximum_population",20))): return false
		if entry.get("behavior","") == "clam":
			if not asset(entry.get("pearl_type",CLAM.pearl_type)): return false
			for key in ["pearl_height","close_distance","open_angle","closed_angle","opening_speed","closing_speed","regrowth_seconds","release_distance"]:
				if not numeric(entry.get(key,CLAM[key]),0,86400): return false
			if float(entry.get("closed_angle",10)) > float(entry.get("open_angle",90)) or float(entry.get("open_angle",90)) > 180: return false
			if float(entry.get("opening_speed",75)) <= 0 or float(entry.get("closing_speed",750)) <= 0 or float(entry.get("regrowth_seconds",7200)) <= 0 or float(entry.get("release_distance",1)) <= 0: return false
		if entry.get("behavior","") == "pearl":
			if not numeric(entry.get("mass",1),0.01,1000) or not asset(entry.get("pickup_commodity","pearls")): return false
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
		if group.has("rotation"):
			if not group.rotation is Array or group.rotation.size() != 3: return false
			for value in group.rotation:
				if not numeric(value,-360,360): return false
		if group.has("initial_delay") and not numeric(group.initial_delay,0,86400): return false
		total += int(group.count)
	return total <= 5000
