extends RefCounted
const ObjectDefinitions = preload("res://object_definitions.gd")
const Mods = preload("res://mod_registry.gd")
const Assets = preload("res://clump_loader.gd")
const Scenery = preload("res://scenery_loader.gd")
const PulseLight = preload("res://pulse_light.gd")
const Searchlight = preload("res://searchlight.gd")
const DEFAULT_PATH := "res://../Maps/scen1.json"
const GROUP_BEHAVIOURS := ["solitary", "shoaling", "schooling"]
const RESPONSES := ["ignore", "flee", "defend", "attack"]
const FOOD_ROLES := ["prey", "predator", "neutral"]
const COMBAT_DEFAULTS := {"bite_damage":5.0,"attack_interval":1.0,"bite_range":0.15,"zapper_range":4.0,"zapper_damage":10.0}
static func creature_ranges(species: Dictionary) -> Dictionary:
	var legacy: Variant = species.get("detection",8.0)
	return {"attack_range":species.get("attack_range",legacy),"flee_range":species.get("flee_range",float(legacy) * 0.5 if legacy is float or legacy is int else legacy)}

static func creature_combat(species: Dictionary) -> Dictionary:
	var model := str(species.get("model","")).trim_prefix("model.").to_lower()
	var defaults := COMBAT_DEFAULTS.duplicate()
	defaults.food_role = "predator" if model in ["piranha","baby","mutant","mjack"] else ("neutral" if model in ["turtle","badthing"] else "prey")
	defaults.has_zapper = model in ["mutant","mjack"]
	for key in defaults: defaults[key] = species.get(key,defaults[key])
	return defaults
const POPULATION_DEFAULTS := {"random_spawn": false, "groups_min": 3, "groups_max": 8, "count_min": 1, "count_max": 10, "spawn_chance": 100.0, "roam_radius": 10.0}
static func empty() -> Dictionary:
	return {"schema_version": 1, "seed": 8675309, "entities": {}, "species": [], "groups": [], "object_types": [ObjectDefinitions.FLOATING_MINE.duplicate(true), ObjectDefinitions.THORIUM.duplicate(true), ObjectDefinitions.inert_thorium()] + ObjectDefinitions.metal_types() + [ObjectDefinitions.CIGARETTE.duplicate(true),ObjectDefinitions.CLAM.duplicate(true),ObjectDefinitions.PEARL.duplicate(true)], "object_groups": []}
static func creature_health(species: Dictionary, catalogue: Dictionary) -> float:
	var stats: Dictionary = catalogue.get("tables",{}).get("creature_stats",{}).get("records",{}).get(str(species.get("model","")).to_lower(),{})
	return maxf(0.1,float(species.get("health",stats.get("health",10.0))))
static func vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
static func array(point: Vector3) -> Array:
	return [point.x, point.y, point.z]
static func encode(pose: Transform3D) -> Array:
	return array(pose.basis.x) + array(pose.basis.y) + array(pose.basis.z) + array(pose.origin)
static func decode(values: Array) -> Transform3D:
	return Transform3D(Basis(vector(values.slice(0, 3)), vector(values.slice(3, 6)), vector(values.slice(6, 9))), vector(values.slice(9, 12)))
static func finite_array(value: Variant, length: int) -> bool:
	if not value is Array or value.size() != length: return false
	for component in value:
		if not (component is float or component is int) or not is_finite(float(component)): return false
	return true
static func valid(data: Variant) -> bool:
	if not data is Dictionary or data.get("schema_version") != 1: return false
	if not ObjectDefinitions.valid(data): return false
	if data.has("menu_camera"):
		if not data.menu_camera is Dictionary or not finite_array(data.menu_camera.get("transform"),12): return false
		var menu_pose := decode(data.menu_camera.transform)
		if not menu_pose.basis.is_equal_approx(menu_pose.basis.orthonormalized()) or menu_pose.basis.determinant() < 0.99: return false
		if not finite_array([data.menu_camera.get("fov")],1) or float(data.menu_camera.fov) < 1.0 or float(data.menu_camera.fov) > 179.0: return false
	if not data.get("entities") is Dictionary or not data.get("species") is Array or not data.get("groups") is Array: return false
	if data.entities.size() > 5000 or data.species.size() > 256 or data.groups.size() > 256: return false
	if not finite_array([data.get("seed", 8675309)], 1): return false
	var ids := {}
	for species in data.species:
		if not species is Dictionary or str(species.get("id", "")).is_empty() or ids.has(species.id): return false
		ids[species.id] = true
		if species.get("food_role","prey") not in FOOD_ROLES: return false
		if species.has("has_zapper") and not species.has_zapper is bool: return false
		for combat_key in COMBAT_DEFAULTS:
			var combat_value: Variant = species.get(combat_key,COMBAT_DEFAULTS[combat_key])
			if not finite_array([combat_value],1) or float(combat_value) < (0.05 if combat_key == "attack_interval" else 0.0) or float(combat_value) > 100000.0: return false
		if species.has("random_spawn") and not species.random_spawn is bool: return false
		if species.has("health") and (not finite_array([species.health],1) or float(species.health) <= 0.0): return false
		for key in ["groups_min","groups_max","count_min","count_max","spawn_chance","roam_radius"]:
			if not finite_array([species.get(key,POPULATION_DEFAULTS[key])],1): return false
		for prefix in ["groups","count"]:
			var minimum := float(species.get(prefix + "_min",POPULATION_DEFAULTS[prefix + "_min"]))
			var maximum := float(species.get(prefix + "_max",POPULATION_DEFAULTS[prefix + "_max"]))
			if minimum != floorf(minimum) or maximum != floorf(maximum) or minimum < (0 if prefix == "groups" else 1) or maximum < minimum or maximum > 100: return false
		if float(species.get("spawn_chance",100.0)) < 0 or float(species.get("spawn_chance",100.0)) > 100: return false
		if float(species.get("roam_radius",10.0)) < 0.5 or float(species.get("roam_radius",10.0)) > 1000: return false
		if str(species.get("model", "")).is_empty() or species.get("mobility") not in ["swimming", "crawling"]: return false
		if species.get("group_behaviour") not in GROUP_BEHAVIOURS or species.get("response") not in RESPONSES: return false
		if not species.has("detection") and (not species.has("attack_range") or not species.has("flee_range")): return false
		if species.has("detection") and (not finite_array([species.detection],1) or float(species.detection) <= 0): return false
		for value in creature_ranges(species).values():
			if not finite_array([value],1) or float(value) <= 0: return false
		for key in ["speed", "scale_min", "scale_max"]:
			if not finite_array([species.get(key)], 1) or float(species[key]) <= 0.0: return false
		if float(species.scale_max) < float(species.scale_min) or float(species.scale_max) > 500.0: return false
		if not finite_array([species.get("animation_speed",1.0)],1) or float(species.get("animation_speed",1.0)) < 0.0 or float(species.get("animation_speed",1.0)) > 10.0: return false
		if not finite_array([species.get("turn_speed", 60.0), species.get("pitch_limit", 25.0)], 2): return false
		if float(species.get("turn_speed", 60.0)) <= 0.0 or float(species.get("turn_speed", 60.0)) > 180.0 or float(species.get("pitch_limit", 25.0)) < 0.0 or float(species.get("pitch_limit", 25.0)) > 60.0: return false
		if not finite_array([species.get("startle_duration", 0.3), species.get("startle_speed_multiplier", 2.8), species.get("startle_turn_speed", 720.0)], 3): return false
		if float(species.get("startle_duration", 0.3)) < 0.0 or float(species.get("startle_duration", 0.3)) > 1.0: return false
		if float(species.get("startle_speed_multiplier", 2.8)) < 1.6 or float(species.get("startle_speed_multiplier", 2.8)) > 6.0: return false
		if float(species.get("startle_turn_speed", 720.0)) < 180.0 or float(species.get("startle_turn_speed", 720.0)) > 1440.0: return false
	var group_ids := {}
	for group in data.groups:
		if not group is Dictionary or not ids.has(group.get("species")) or str(group.get("id", "")).is_empty() or group_ids.has(group.id): return false
		group_ids[group.id] = true
		if not finite_array(group.get("position"), 3): return false
		for key in ["chance", "count_min", "count_max", "radius"]:
			if not finite_array([group.get(key)], 1): return false
		if group.chance < 0 or group.chance > 100 or group.radius < 0.5 or group.radius > 1000: return false
		if group.count_min < 1 or group.count_max > 100 or group.count_max < group.count_min: return false
		if group.has("overrides"):
			if not group.overrides is Dictionary: return false
			for key in group.overrides:
				if key not in ["scale_min", "scale_max", "group_behaviour", "response"]: return false
			var effective: Dictionary = data.species.filter(func(species: Dictionary) -> bool: return species.id == group.species)[0].duplicate(true)
			effective.merge(group.overrides, true)
			if effective.group_behaviour not in GROUP_BEHAVIOURS or effective.response not in RESPONSES: return false
			if not finite_array([effective.scale_min, effective.scale_max], 2) or effective.scale_min <= 0 or effective.scale_max < effective.scale_min or effective.scale_max > 500: return false
	for key in data.entities:
		if (key != "player_spawn" and not str(key).begins_with("Scenery/") and not str(key).begins_with("Added/")) or str(key).contains("..") or str(key).contains(":"): return false
	for entity in data.entities.values():
		if not entity is Dictionary or not finite_array(entity.get("transform"), 12): return false
		if absf(decode(entity.transform).basis.determinant()) < 0.00001: return false
		if entity.get("kind") not in ["model", "light", "player", "dropoff"]: return false
		if entity.kind == "dropoff":
			if not ObjectDefinitions.numeric(entity.get("radius"),0.01,1000) or not ObjectDefinitions.numeric(entity.get("city_id",0),0,1000000000000): return false
		if entity.kind == "light":
			if entity.get("light_type", "beacon") not in ["beacon", "searchlight"]: return false
			if entity.get("light_type", "beacon") == "searchlight":
				for property in Searchlight.DEFAULTS:
					var limits: Array = {"sweep_speed":[0,180], "sweep_angle":[0,180], "beam_length":[0.1,100], "beam_width":[0.02,50], "beam_brightness":[0,4], "beam_softness":[0.05,1], "day_brightness":[0,1]}[property]
					if not ObjectDefinitions.numeric(entity.get(property, Searchlight.DEFAULTS[property]), limits[0], limits[1]): return false
				continue
			if entity.has("pulse_enabled") and not entity.pulse_enabled is bool: return false
			if PulseLight.mode_from(entity) not in ["steady", "pulsing", "flashing"]: return false
			for property in ["energy", "range", "pulse_period", "pulse_minimum", "flare_size", "flash_on_time", "flash_off_time"]:
				if entity.has(property) and not finite_array([entity[property]], 1): return false
			for property in ["flash_on_time", "flash_off_time"]:
				if entity.has(property) and (float(entity[property]) < 0.05 or float(entity[property]) > 60.0): return false
			if float(entity.get("pulse_period", 2.4)) < 0.1 or float(entity.get("pulse_period", 2.4)) > 60.0: return false
			if float(entity.get("pulse_minimum", 0.2)) < 0.0 or float(entity.get("pulse_minimum", 0.2)) > 1.0: return false
			if float(entity.get("flare_size", 4.0)) < 0.1 or float(entity.get("flare_size", 4.0)) > 100.0: return false
		if entity.has("dock"):
			if not entity.dock is Dictionary or not finite_array([entity.dock.get("city_id"), entity.dock.get("race_id")], 2): return false
	return true
static func load_path(path: String) -> Dictionary:
	path = preload("res://runtime_paths.gd").external(path)
	if not FileAccess.file_exists(path): return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not valid(data): Mods.note("Invalid map file; keeping the next map or original world: " + path); return {}
	# Earlier editor builds captured the recovered cones as scenery models.
	for key in data.entities:
		var entry: Dictionary = data.entities[key]
		if str(key).begins_with("Scenery/Searchlight_") and entry.kind == "model" and str(entry.get("model", "")).to_upper() == "BIGLITE":
			entry.kind = "light"; entry.light_type = "searchlight"; entry.solid = false
	ObjectDefinitions.ensure(data)
	return data
static func load_active(include_mod_wildlife: bool = true) -> Dictionary:
	for entry in Mods.candidates("map.scen1"):
		var data := load_path(entry.path)
		if not data.is_empty(): return _add_mod_wildlife(data) if include_mod_wildlife else data
	var data := load_path(DEFAULT_PATH)
	return _add_mod_wildlife(data) if include_mod_wildlife else data
static func save(data: Dictionary, path: String = DEFAULT_PATH) -> Error:
	if not valid(data): return ERR_INVALID_DATA
	var absolute := preload("res://runtime_paths.gd").external(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute + ".tmp", FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "  ") + "\n")
	file.close()
	return DirAccess.rename_absolute(absolute + ".tmp", absolute)
static func capture(world: Node3D, catalogue: Dictionary = {}) -> Dictionary:
	var data := empty()
	for node in world.find_children("*", "Node3D", true, false):
		if not node.has_meta("editor_model") and not node.has_meta("editor_dropoff") and not node is OmniLight3D and not node is Searchlight: continue
		var key := str(world.get_path_to(node))
		# Creature-attached lights (such as an angler's lure) are not map entities.
		if not key.begins_with("Scenery/") and not key.begins_with("Added/"): continue
		var record := {"name": str(node.get_meta("city_name", node.name)), "kind": "dropoff" if node.has_meta("editor_dropoff") else ("light" if node is OmniLight3D or node is Searchlight else "model"), "model": str(node.get_meta("editor_model", "")), "transform": encode(node.global_transform), "deleted": false, "solid": node.has_node("SceneryCollision")}
		if node.has_meta("editor_dropoff"):
			record.radius = node.radius; record.city_id = node.city_id
			var city: Dictionary = catalogue.get("tables",{}).get("city_info",{}).get("records",{}).get(str(node.city_id),{})
			record.name = str(city.get("name","City " + str(node.city_id))) + " drop-off point"
		if node.has_meta("city_id"): record.dock = {"city_id": int(node.get_meta("city_id")), "race_id": int(node.get_meta("race_id", 1))}
		if node is PulseLight or node is Searchlight: record.merge(node.settings())
		elif node is OmniLight3D: record.merge({"energy": node.light_energy, "range": node.omni_range})
		data.entities[key] = record
	data.entities["player_spawn"] = {"name": "Player spawn", "kind": "player", "transform": encode(Transform3D(world.get_meta("player_spawn_basis",Basis.IDENTITY), world.get_meta("player_spawn"))), "deleted": false}
	return data
static func load_model(id: String, folder: String, animated: bool = false) -> Node3D:
	# Model IDs resolve enabled modern replacements through the existing loader.
	if id.to_lower().begins_with("model."): id = id.substr(6)
	if id.contains("/") or id.contains("\\") or id.contains("..") or id.contains(":"): return null
	return Assets.load_clump(folder.path_join("CLUMPS/" + id.to_upper().trim_suffix(".DFF") + ".DFF"), PackedStringArray(), animated)
static func apply_entities(world: Node3D, folder: String, data: Dictionary) -> void:
	for key in data.entities:
		var entry: Dictionary = data.entities[key]
		if entry.kind == "player":
			if not entry.get("deleted", false):
				var pose := decode(entry.transform)
				world.set_meta("player_spawn",pose.origin)
				world.set_meta("player_spawn_basis",pose.basis.orthonormalized())
			continue
		var node := world.get_node_or_null(NodePath(str(key))) as Node3D
		if entry.get("deleted", false):
			if node != null: node.free()
			continue
		if node == null and str(key).begins_with("Added/"):
			if not world.has_node("Added"):
				var added := Node3D.new(); added.name = "Added"; world.add_child(added)
			node = preload("res://drop_off_point.gd").new() if entry.kind == "dropoff" else ((Searchlight.new() if entry.get("light_type") == "searchlight" else PulseLight.new()) if entry.kind == "light" else load_model(str(entry.get("model", "")), folder, entry.has("dock")))
			if node == null: continue
			node.name = str(key).get_file()
			world.get_node("Added").add_child(node)
			if entry.kind == "model":
				node.set_meta("editor_model", entry.model)
				if entry.get("solid", true): Scenery._add_prop_collision(node)
		if node == null: continue
		if entry.kind == "light" and ((entry.get("light_type") == "searchlight") != (node is Searchlight)):
			var replacement: Node3D = Searchlight.new() if entry.get("light_type") == "searchlight" else PulseLight.new()
			var parent := node.get_parent(); var original_name := node.name
			node.free(); replacement.name = original_name; parent.add_child(replacement); node = replacement
		if entry.has("dock"):
			node.set_meta("city_id", int(entry.dock.city_id)); node.set_meta("race_id", int(entry.dock.race_id)); node.set_meta("city_name", str(entry.name))
		if entry.kind == "model" and str(node.get_meta("editor_model", "")) != str(entry.get("model", "")) and not node.has_meta("city_id"):
			var replacement := load_model(str(entry.model), folder)
			if replacement != null:
				var parent := node.get_parent(); var original_name := node.name
				node.free(); replacement.name = original_name; parent.add_child(replacement); node = replacement
				node.set_meta("editor_model", entry.model)
				if entry.get("solid", true): Scenery._add_prop_collision(node)
		if entry.kind == "dropoff": node.configure(float(entry.radius),int(entry.get("city_id",0)))
		node.global_transform = decode(entry.transform)
		if node is PulseLight or node is Searchlight:
			node.configure(folder, entry)
		elif node is OmniLight3D:
			node.light_energy = clampf(float(entry.get("energy", 1.0)), 0.0, 16.0)
			node.omni_range = clampf(float(entry.get("range", 5.0)), 0.1, 1000.0)

static func _add_mod_wildlife(data: Dictionary) -> Dictionary:
	if data.is_empty(): return data
	var additions_in_order := Mods.candidates("data.wildlife")
	additions_in_order.reverse()
	for entry in additions_in_order:
		var additions: Variant = JSON.parse_string(FileAccess.get_file_as_string(entry.path))
		if not additions is Dictionary or additions.get("schema_version") != 1 or not additions.get("species") is Array:
			Mods.note("Invalid wildlife additions: " + str(entry.path)); continue
		var candidate := data.duplicate(true)
		# An enabled pack overrides matching map definitions, including mod
		# species accidentally included in maps saved by older editor versions.
		var replacement_ids := {}
		for species in additions.species:
			if species is Dictionary: replacement_ids[str(species.get("id",""))] = true
		candidate.species = candidate.species.filter(func(species: Dictionary) -> bool: return not replacement_ids.has(str(species.id)))
		candidate.species.append_array(additions.species)
		if not valid(candidate):
			Mods.note("Invalid or duplicate creature definitions in " + str(entry.name)); continue
		data = candidate
	return data
