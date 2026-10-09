extends SceneTree
const Editor = preload("res://asset_editor.gd")
const Document = preload("res://map_document.gd")
const Mods = preload("res://mod_registry.gd")
const Game = preload("res://game.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(message)
func _run() -> void:
	Mods.initialize(false)
	var editor := Editor.new(); editor.remember_preferences = false; root.add_child(editor)
	await process_frame
	editor._set_mode(true)
	var map: HBoxContainer = editor.map_editor
	for frame in range(1800):
		if map.loaded or (not map.loading and not map.document.is_empty()): break
		await physics_frame
	check(map.loaded, "Map mode loads terrain and original scenery")
	if not map.loaded: quit(1); return
	check(map.document.entities.size() > 380 and map.document.species.size() >= 8 and map.document.groups.is_empty(), "Scenery and creature types load without the removed fixed wildlife groups")
	check(Document.valid(map.document), "Seeded editor document validates")
	check(map.entity_list.item_count > 380, "Unfiltered entity list is populated")
	check(not map.population.simulating, "Wildlife stays still while editing")
	var searchlights: Array = map.document.entities.keys().filter(func(id: String) -> bool: return map.document.entities[id].get("light_type") == "searchlight")
	check(searchlights.size() == 10, "Original searchlights are imported as light entities")
	map.category.select(2); map._refresh_list()
	check(searchlights.all(func(id: String) -> bool: return map.list_keys.has(id)), "Searchlights appear under Lights")
	var beam_key: String = searchlights[0]; map.select(beam_key)
	check(map.fields.sweep_speed.visible and not map.fields.energy.visible and map.fields.rotation_1.visible, "Searchlight controls replace beacon controls and retain orientation")
	check(map.fields.sweep_speed.value == 15, "Default searchlight sweep speed is halved")
	if DisplayServer.get_name() != "headless":
		for frame in range(5): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/searchlight-editor.png")
	map.fields.sweep_speed.value = 9; map.fields.sweep_angle.value = 30
	map.fields.beam_width.value = 1.4; map.fields.beam_softness.value = 0.8; map.fields.day_brightness.value = 0.1
	map.fields.rotation_1.value += 15; map.apply_properties()
	var beam: Node3D = map.world.get_node(NodePath(beam_key))
	check(beam.sweep_speed == 9 and is_equal_approx(beam.tuning.beam_width, 1.4) and is_equal_approx(beam.tuning.day_brightness, 0.1), "Searchlight edits update the preview")
	var beam_path := "res://tests/searchlight-roundtrip.json"
	check(Document.save(map.document, beam_path) == OK, "Map saves with searchlight properties")
	var beam_document := Document.load_path(beam_path)
	check(beam_document.entities[beam_key].beam_softness == 0.8 and beam_document.entities[beam_key].sweep_speed == 9, "Searchlight tuning survives save/load")
	map.duplicate_selection()
	var copy: Node3D = map.world.get_node(NodePath(map.selected))
	check(copy is Document.Searchlight and copy.material != beam.material and copy.sweep_speed == 9, "Duplicating a beam preserves settings with independent shader resources")
	map.undo(); map.undo(); map.select(beam_key)
	check(map.world.get_node(NodePath(beam_key)).sweep_speed == 15, "Undo restores original searchlight tuning")
	var bad_beam := beam_document.duplicate(true); bad_beam.entities[beam_key].beam_softness = -1
	check(not Document.valid(bad_beam), "Malformed beam settings are rejected")
	var legacy_beam := beam_document.duplicate(true); legacy_beam.entities[beam_key].kind = "model"; legacy_beam.entities[beam_key].erase("light_type")
	Document.save(legacy_beam, beam_path)
	check(Document.load_path(beam_path).entities[beam_key].light_type == "searchlight", "Older cone model records migrate into Lights")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(beam_path))
	map.category.select(0); map._refresh_list()
	map.select("player_spawn")
	check(map.fields.has("facing"), "Player spawn exposes facing in object properties")
	var spawn_before := Document.decode(map.record().transform)
	map.fields.facing.value = 90; map.apply_properties()
	var spawn_after := Document.decode(map.record().transform)
	check((-spawn_after.basis.z).is_equal_approx(Vector3.RIGHT) and spawn_after.origin.is_equal_approx(spawn_before.origin), "Clockwise facing changes spawn direction without moving it")
	check(map.world.get_meta("player_spawn_basis").is_equal_approx(spawn_after.basis), "Editor applies spawn facing to the world")
	var spawn_path := "res://tests/spawn-facing-roundtrip.json"
	check(Document.save(map.document,spawn_path) == OK and Document.decode(Document.load_path(spawn_path).entities.player_spawn.transform).basis.is_equal_approx(spawn_after.basis), "Spawn facing survives map save and reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(spawn_path))
	map.undo()
	check(Document.decode(map.document.entities.player_spawn.transform).is_equal_approx(spawn_before), "Undo restores spawn facing")
	var drops: Array = map.document.entities.keys().filter(func(id: String) -> bool: return map.document.entities[id].kind == "dropoff")
	check(drops.size() == 5, "Five original city drop-off points are imported")
	var drop_key: String = drops[0]; map.category.select(5); map._refresh_list(); map.select(drop_key)
	check(map.list_keys.has(drop_key) and map.fields.has("radius") and not map.fields.has("model"), "Objects list exposes detection position and size without duplicating the existing pad model")
	var drop_origin: Vector3 = map.point()
	map.fields.radius.value = 1.25; map.fields.position_1.value += 0.5; map.apply_properties()
	var drop_node: Area3D = map.world.get_node(NodePath(drop_key))
	check(is_equal_approx(drop_node.radius,1.25) and absf(drop_node.position.y - drop_origin.y - 0.5) < 0.06, "Editor applies detection size and vertical position")
	check(drop_node.collision_layer == 0 and not drop_node.monitoring, "Delivery zones do not physically block movement")
	var drop_path := "res://tests/dropoff-roundtrip.json"
	check(Document.save(map.document,drop_path) == OK and is_equal_approx(Document.load_path(drop_path).entities[drop_key].radius,1.25), "Drop-off properties survive saving and loading")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(drop_path))
	map.undo(); map.category.select(0); map._refresh_list()
	var key := ""
	for candidate in map.document.entities:
		if map.document.entities[candidate].kind == "model" and not map.document.entities[candidate].deleted and map.base_nodes.has(candidate) and not map.base_nodes[candidate].has_meta("city_id"): key = candidate; break
	map.select(key)
	var before: Vector3 = map.point()
	map.fields.position_0.value += 2.0; map.apply_properties()
	check(absf(map.point().x - before.x - 2) < 0.06, "Position properties move an original entity")
	map.undo(); check(map.point().is_equal_approx(before), "Undo restores original entity position")
	map.redo(); check(absf(map.point().x - before.x - 2) < 0.06, "Redo reapplies the move")
	map.delete_selection(); check(map.document.entities[key].deleted and map.world.get_node_or_null(NodePath(key)) == null, "Deleting original scenery creates a persistent removal override")
	map.undo(); check(map.world.get_node_or_null(NodePath(key)) != null, "Undo restores deleted original scenery")
	map.select(key); map.duplicate_selection()
	check(map.selected.begins_with("Added/") and map.world.get_node_or_null(NodePath(map.selected)) != null, "Duplicate adds a model through the same runtime map format")
	map.add_species(); var species_key: String = map.selected
	check(map.species_preview != null and map.species_preview.model != null,"Creature properties show the selected model")
	check(map.fields.has("health") and is_equal_approx(map.fields.health.value,Document.creature_health(map.record(),map.gameplay_catalogue)),"Creature editor displays the same health default used by gameplay")
	map.fields.animation_speed.value = 2.5
	map.fields.food_role.select(Document.FOOD_ROLES.find("predator")); map.fields.has_zapper.button_pressed = true
	map.fields.bite_damage.value = 7; map.fields.attack_interval.value = 0.5
	map.fields.zapper_range.value = 6; map.fields.zapper_damage.value = 12
	check(map.fields.has("flee_range") and map.fields.has("attack_range") and not map.fields.has("detection"),"Creature editor exposes separate flee and attack detection ranges")
	map.fields.flee_range.value = 2; map.fields.attack_range.value = 9
	check(is_equal_approx(map.species_preview.animation_speed,2.5),"Animation speed updates the creature preview")
	map.apply_properties()
	check(is_equal_approx(map.record().animation_speed,2.5) and Document.valid(map.document),"Animation speed is saved in valid species settings")
	check(map.record().food_role == "predator" and map.record().has_zapper and map.record().bite_damage == 7 and map.record().attack_interval == 0.5 and map.record().zapper_range == 6 and map.record().zapper_damage == 12,"Editor stores configurable wildlife role, bites and optional zapper")
	var turtle_index: int = map.models.find("TURTLE")
	map.fields.model.select(turtle_index); map.fields.model.item_selected.emit(turtle_index)
	check(str(map.species_preview.model.get_meta("asset_source")).ends_with("TURTLE.DFF"),"Changing the model updates the preview before applying")
	map.fields.model.select(map.models.find("ANGEL"))
	check(map.entity_list.item_count == map.document.species.size(), "Creature type filter lists all definitions")
	map.fields.name.text = "Test shoal"; map.fields.scale_min.value = 40; map.fields.scale_max.value = 60; map.fields.health.value = 45.0
	map.apply_properties()
	check(map.record().scale_min == 40 and map.record().scale_max == 60, "Creature types store percentage scale ranges")
	check(map.record().health == 45.0,"Creature types store editable health")
	map.add_group(); var group_key: String = map.selected
	check(map.record().species == species_key.trim_prefix("species:"), "Adding a group uses the selected creature type")
	check(map.fields.species.get_item_text(map.fields.species.selected) == "Test shoal" and map.fields.species.get_item_text(0) == "Angel", "Creature dropdown displays names for custom and built-in species")
	map.fields.species.select(0)
	check(map._value("species") == map.document.species[0].id, "Dropdown stores the stable species ID independently of the display name")
	map.select(species_key); map.fields.name.text = "Turtle"; map.apply_properties(); map.select(group_key)
	check(map.fields.species.get_item_text(map.fields.species.selected) == "Turtle" and map.record().species == species_key.trim_prefix("species:"), "Renaming a creature updates its dropdown label without breaking group references")
	var safe_home: Array = map.population.random_groups[0].group.position.duplicate()
	for i in range(3): map.fields["position_" + str(i)].value = safe_home[i]
	map.fields.chance.value = 0; map.fields.count_min.value = 1; map.fields.count_max.value = 1; map.apply_properties()
	check(not map.population.spawned_groups.has(group_key.trim_prefix("group:")), "Zero-percent chance never spawns the group")
	map.fields.chance.value = 100; map.apply_properties()
	check(map.population.spawned_groups.has(group_key.trim_prefix("group:")), "Hundred-percent chance spawns in clear water")
	var members: Array = map.population.get_children().filter(func(fish: Node3D) -> bool: return fish.get_meta("spawn_group","") == group_key.trim_prefix("group:"))
	check(not members.is_empty() and members.all(func(fish: Node3D) -> bool: return fish.max_health == 45.0),"Spawned creatures use the health set in the editor")
	map.fields.overrides_enabled.button_pressed = true
	map.fields.scale_min.value = 50; map.fields.scale_max.value = 55; map.apply_properties()
	check(map.record().overrides.scale_min == 50, "Individual groups can override species size and behaviour")
	var path := "res://tests/editor-map.json"
	check(Document.save(map.document, path) == OK, "Map saves to JSON")
	var restored := Document.load_path(path)
	check(not restored.is_empty() and restored.species[-1].health == 45.0,"Creature health survives saving and loading the map")
	check(restored.species[-1].food_role == "predator" and restored.species[-1].has_zapper and restored.species[-1].zapper_damage == 12,"Combat settings survive saving and loading")
	check(restored.species[-1].flee_range == 2 and restored.species[-1].attack_range == 9 and not restored.species[-1].has("detection"),"Independent perception ranges survive saving and loading")
	check(not restored.is_empty() and restored.entities.size() == map.document.entities.size() and restored.groups.size() == map.document.groups.size() and restored.species[-1].name == "Turtle" and Document.decode(restored.entities[key].transform).is_equal_approx(Document.decode(map.document.entities[key].transform)), "Map properties survive a JSON round trip")
	var invalid: Dictionary = map.document.duplicate(true)
	invalid.species[0].health = 0.0
	check(not Document.valid(invalid),"Invalid creature health is rejected")
	invalid = map.document.duplicate(true)
	invalid.groups[0].chance = 101
	check(not Document.valid(invalid), "Invalid chance is rejected")
	invalid = map.document.duplicate(true); invalid.entities["../outside"] = invalid.entities[key]
	check(not Document.valid(invalid), "Map entities cannot escape the scenery hierarchy")
	var pop: Node3D = map.population
	var generation: int = pop.generation
	pop.reroll(); check(pop.generation == generation + 1, "Population reroll advances the generation once")
	var signature: Array = pop.get_children().map(func(fish: Node3D) -> Vector3: return fish.position)
	pop.reroll(false)
	check(pop.get_children().map(func(fish: Node3D) -> Vector3: return fish.position) == signature, "Same map seed and generation reproduce the same population")
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1280,720)
		map.category.select(4); map._refresh_list()
		for creature in map.document.species:
			if creature.model == "TURTLE": map.select("species:" + str(creature.id)); break
		for frame in range(5): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/species-population-preview.png")
	map.select("object_type:coin")
	check(map.fields.has("delivery_commodity") and map.fields.has("delivery_quantity") and map.fields.delivery_quantity.value == 2,"Object editor exposes delivery commodity and units")
	for index in range(map.fields.delivery_commodity.item_count):
		if map.fields.delivery_commodity.get_item_metadata(index) == "metal": map.fields.delivery_commodity.select(index); break
	map.fields.delivery_quantity.value = 7; map.apply_properties()
	check(map.record().delivery_commodity == "metal" and map.record().delivery_quantity == 7,"Editor can change the coin's commodity and delivery quantity")
	Document.save(map.document,path)
	var delivery_document := Document.load_path(path)
	check(delivery_document.object_types.any(func(type: Dictionary) -> bool: return type.id == "coin" and type.delivery_commodity == "metal" and type.delivery_quantity == 7),"Delivery properties survive a map export and reload")
	map.select("object_type:cigarette_end")
	check(map.fields.grapple_compatible.button_pressed and not map.fields.magnet_compatible.button_pressed,"Cigarette editor exposes independent grapple and magnet flags")
	check(map.record().delivery_commodity == "tobacco" and map.fields.delivery_quantity.value == 1,"Cigarette delivery commodity and amount are editable")
	map.fields.grapple_compatible.button_pressed = false; map.fields.magnet_compatible.button_pressed = true; map.apply_properties()
	Document.save(map.document,path)
	var grapple_document := Document.load_path(path)
	check(grapple_document.object_types.any(func(type: Dictionary) -> bool: return type.id == "cigarette_end" and not type.grapple_compatible and type.magnet_compatible),"Both compatibility flags persist through map save and reload")
	map.select("object_type:thorium")
	check(map.fields.grapple_compatible.button_pressed and not map.fields.magnet_compatible.button_pressed,"Whole thorium defaults to grapple-only retrieval")
	map.select("object_type:clam")
	check(not map.fields.has("health") and not map.fields.has("magnet_compatible") and not map.fields.has("delivery_commodity"),"Static clams hide unsupported health, towing and delivery controls")
	check(map.fields.has("regrowth_seconds") and map.fields.has("close_distance") and map.fields.has("opening_speed"),"Clam behaviour is editable")
	map.fields.regrowth_seconds.value = 60; map.apply_properties()
	check(map.record().regrowth_seconds == 60,"Clam timing edits apply")
	map.document.object_groups.append({"id":"editable_clam","name":"Clam","type":"clam","count":1,"radius":0,"position":[0,0,0]})
	map.select("object_group:editable_clam")
	check(map.fields.has("initial_delay") and map.fields.has("group_rotation_1"),"Clam placement exposes first pearl delay and rotation")
	map.fields.initial_delay.value = 12; map.fields.group_rotation_1.value = 45; map.apply_properties()
	Document.save(map.document,path)
	var clam_document := Document.load_path(path)
	check(clam_document.object_groups.any(func(group: Dictionary) -> bool: return group.id == "editable_clam" and group.initial_delay == 12 and group.rotation[1] == 45),"Clam placement edits survive export")
	map.select("object_type:pearl")
	check(map.fields.has("mass") and map.fields.has("pickup_commodity"),"Pearl physics and collected commodity are editable")
	check(not map.fields.has("health"),"Invulnerable pearls do not expose unused health")
	var mine_types: Array = map.document.object_types.filter(func(type: Dictionary) -> bool: return type.get("behavior", "mine") == "mine")
	check(not mine_types.is_empty(),"Mine fixture is available")
	if not mine_types.is_empty():
		map.select("object_type:" + str(mine_types[0].id))
		check(map.fields.has("health") and not map.fields.has("grapple_compatible") and not map.fields.has("delivery_commodity"),"Mines expose damageable health without unsupported towing or delivery controls")
	map.choice("missing_model_fixture","Model",["ANGEL","JACKFISH"],"custom_fish")
	check(map._value("missing_model_fixture") == "custom_fish","An unavailable model ID survives dropdown creation without becoming the first original model")
	editor.queue_free(); await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Map editor verification: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
