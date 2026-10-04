extends SceneTree
const Editor = preload("res://asset_editor.gd")
const Game = preload("res://game.gd")
const Document = preload("res://map_document.gd")
const Mods = preload("res://mod_registry.gd")
const Docking = preload("res://docking_controller.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(message)
func _run() -> void:
	Mods.initialize(false)
	var editor := Editor.new(); editor.remember_preferences = false; root.add_child(editor)
	await process_frame; editor._set_mode(true)
	for frame in range(1800):
		if editor.map_editor.loaded: break
		await physics_frame
	var data: Dictionary = editor.map_editor.document.duplicate(true)
	var home: Array = editor.map_editor.population.random_groups[0].group.position.duplicate()
	for species in data.species: species.random_spawn = false
	data.groups = [{"id":"fixed_test", "name":"Fixed test","species":data.species[0].id,"position":home,"chance":100.0,"count_min":2,"count_max":4,"radius":10.0}]
	data.groups[0].chance = 100; data.groups[0].count_min = 2; data.groups[0].count_max = 4
	data.species[0].scale_min = 40; data.species[0].scale_max = 60
	data.entities["Added/test_light"] = {"name": "Test lamp", "kind": "light", "transform": Document.encode(Transform3D(Basis.IDENTITY, Document.vector(home))), "energy": 1.5, "range": 9.0}
	for key in data.entities.keys():
		if data.entities[key].has("dock"):
			var copy: Dictionary = data.entities[key].duplicate(true); copy.dock.city_id = 100; copy.name = "Test dock"; copy.transform[9] += 30
			data.entities["Added/test_dock"] = copy; break
	var removed := ""
	for key in data.entities:
		if data.entities[key].kind == "model" and str(key).contains("Plant_"): removed = key; data.entities[key].deleted = true; break
	editor.queue_free(); await process_frame
	var pack_dir := "res://tests/wildlife-fixtures/map-test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(pack_dir))
	Document.save(data, pack_dir.path_join("map.json"))
	var manifest := FileAccess.open(pack_dir.path_join("mod.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"schema_version": 1, "id": "map-test", "name": "Map test", "assets": {"map.scen1": "map.json"}})); manifest.close()
	Mods.initialize(false, "res://tests/wildlife-fixtures", "res://tests/wildlife-test-prefs.cfg")
	Mods.apply(["map-test"], Mods.order, false)
	check(Mods.candidates("map.scen1").size() == 1, "Map overrides are accepted as mod assets")
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(1800):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete and game.wildlife != null, "Game loads authored wildlife from an enabled map mod")
	check(game.world_root.get_node_or_null(NodePath(removed)) == null and game.world_root.has_node("Added/test_light"), "Map removals and added light affect the game world")
	check(game.docking.ports.size() == 7 and game.docking.ports.any(func(port: Dictionary) -> bool: return port.name == "Test dock"), "Duplicated docks retain working docking components")
	var pop: Node3D = game.wildlife
	check(pop.get_child_count() >= 2 and pop.get_child_count() <= 4 and pop.spawned_groups == [data.groups[0].id], "Only the eligible group spawns and respects population range")
	var model_scale: float = pop.templates[data.species[0].id].scale.x
	check(pop.get_children().all(func(fish: Node3D) -> bool: return fish.get_child(1).scale.x >= model_scale * 0.4 and fish.get_child(1).scale.x <= model_scale * 0.6), "Per-creature scale falls inside the authored range")
	var creature: CharacterBody3D = pop.get_child(0)
	creature.group_behaviour = "solitary"; creature.home = creature.position
	game.pilot.global_position = creature.global_position + Vector3(0, 0, -3)
	creature.response = "flee"; creature.direction = Vector3.BACK; creature._physics_process(0.1)
	check(creature.direction.dot((game.pilot.global_position - creature.global_position).normalized()) < 0, "Fleeing turns away from the nearby submarine")
	creature.response = "attack"; creature.direction = Vector3.FORWARD; creature._physics_process(0.1)
	check(creature.direction.dot((game.pilot.global_position - creature.global_position).normalized()) > 0, "Aggressive creatures pursue a nearby submarine")
	creature.response = "ignore"; creature.mobility = "crawling"; creature._physics_process(0.1)
	var contact: Dictionary = pop.floor_contact(creature.global_position)
	check(not contact.is_empty() and absf((creature.global_position - Vector3(contact.position)).dot(contact.normal) - creature.ground_clearance) < 0.01 and creature.basis.y.dot(contact.normal) > 0.999 and is_zero_approx(creature.direction.y), "Crawling wildlife stays grounded and aligns with the seabed")
	game.set_process(false); game.set_physics_process(false); game.docking.set_physics_process(false)
	var generation: int = pop.generation
	game.docking.current = game.docking.ports[0]
	game.docking.transit_settings = game.pilot.movement.settings.duplicate()
	game.docking._transition(Docking.Stage.CLOSE)
	game.docking._physics_process(0.6)
	check(pop.generation == generation and not game.docked_screen.visible, "Population stays unchanged while doors are still closing")
	game.docking._physics_process(0.7)
	check(pop.generation == generation + 1 and game.docked_screen.visible and game.docking.stage == Docking.Stage.DOCKED, "Doors fully closed triggers exactly one hidden-world reroll")
	game.docking._physics_process(2.0)
	check(pop.generation == generation + 1, "Remaining docked does not keep rerolling")
	pop.document.groups[0].chance = 50
	var appeared := 0
	for cycle in range(100):
		pop.reroll()
		if not pop.spawned_groups.is_empty(): appeared += 1
	check(appeared > 30 and appeared < 70, "Fifty-percent chance produces varied populations across docking cycles")
	pop.document.groups[0].chance = 0; pop.reroll()
	check(pop.get_child_count() == 0, "Zero chance removes the group on the next reroll")
	game.queue_free(); await process_frame
	await create_timer(0.25).timeout
	for path in [pack_dir.path_join("map.json"), pack_dir.path_join("mod.json")]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pack_dir))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://tests/wildlife-fixtures"))
	Mods.initialize(false)
	print("Wildlife world verification: %d checks, %d failures; 50%% group appeared %d / 100" % [checks, failures, appeared])
	quit(1 if failures else 0)
