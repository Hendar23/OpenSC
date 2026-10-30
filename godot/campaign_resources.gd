extends RefCounted
## Retail 0046ae40 -> 00438360 -> 0041a1e0: once-only, unowned bonus objects.
const OPENING_BONUS := "opening_bonus"
const GROUP := "campaign/opening_bonus"
const GENOCIDE_GROUP := "campaign/genocide_bonus"

static func restore_for_progress(game: Node) -> void:
	_restore_starting_coins(game)
	# Published betas removed these objects on completion. Seed missing world
	# resources once for an existing post-opening save, independent of mail.
	var missions: Dictionary = game.player_progress.missions
	var started := int(game.player_progress.campaign_stage) > 1
	for id in ["tradetrad","tradetrad2","tradetech","tradetech2"]:
		started = started or missions.completed.has(id) or str(missions.active.get("id","")) == id
	if started: spawn_opening_bonus(game)
	var walker_started := int(game.player_progress.campaign_stage) >= 3
	for id in ["walktrad","walktrad2","walktech","walktech2"]:
		walker_started = walker_started or missions.completed.has(id) or str(missions.active.get("id","")) == id
	if walker_started: spawn_genocide_bonus(game)

# The FAQ confirms three coins in the tin can. Their editable placements live
# in the map; this only seeds the omitted objects once in published beta saves.
static func _restore_starting_coins(game: Node) -> void:
	var missions: Dictionary = game.player_progress.missions
	var events: Dictionary = missions.get("world_events",{})
	if events.get("tin_can_coins",false): return
	var population: Node = game.object_population
	var entries: Array = population.initial_thorium.filter(func(entry: Dictionary) -> bool: return str(entry.get("object_group","")).begins_with("original_tin_coin_"))
	if entries.is_empty(): return # Respect maps which omit this stash.
	var existing := population.get_children().any(func(body: Node) -> bool: return str(body.get_meta("object_group","")).begins_with("original_tin_coin_"))
	if not existing:
		var created: Array[Node] = []
		for entry in entries:
			var body: Node = population._create_thorium(entry.stats,0,preload("res://map_document.gd").decode(entry.pose))
			if body == null:
				for node in created: node.free()
				return
			body.set_meta("object_group",entry.object_group)
			preload("res://entity_identity.gd").assign_id(body,entry.entity_id)
			created.append(body)
	events["tin_can_coins"] = true
	missions["world_events"] = events

static func spawn_opening_bonus(game: Node) -> void:
	_spawn_bonus(game,33,OPENING_BONUS,GROUP)

static func spawn_genocide_bonus(game: Node) -> void:
	_spawn_bonus(game,5,"genocide_bonus",GENOCIDE_GROUP)

static func _spawn_bonus(game: Node, mission_id: int, event: String, group: String) -> void:
	var missions: Dictionary = game.player_progress.missions
	var events: Dictionary = missions.get("world_events",{}) if missions.get("world_events",{}) is Dictionary else {}
	if events.get(event,false) == true: return
	var population: Node = game.object_population
	var existing := false
	for body in population.get_children():
		if body.get_meta("object_group","") == group or str(body.get_meta("source_entity_id","")).begins_with(group + "/"):
			existing = true; break
	if not existing:
		var definitions = preload("res://object_definitions.gd")
		var offset: Vector3 = game.world_root.get_meta("database_offset",Vector3.ZERO)
		var created: Array[Node] = []
		for row in game.gameplay_catalogue.tables.get("database.objects",{}).get("records",{}).values():
			if int(row.get("MissionID",0)) != mission_id or int(row.get("AutoCreate",0)) != 1: continue
			var definition := {}
			match int(row.get("ObjectType",0)):
				63: definition = population.thorium_types.get("thorium",definitions.THORIUM)
				64: definition = population.thorium_types.get("inert_thorium",definitions.inert_thorium(population.thorium_types.get("thorium",definitions.THORIUM)))
				86: definition = population.salvage_types.get("bottletop",definitions.SALVAGE)
				95: definition = population.salvage_types.get("coin",definitions.metal_types()[2])
			if definition.is_empty(): continue
			var pose := preload("res://scenery_loader.gd").placement(row,offset)
			var body: Node = population._create_thorium(definition,0,pose)
			if body == null:
				for node in created: node.free()
				return
			body.set_meta("object_group",group)
			preload("res://entity_identity.gd").assign_id(body,group + "/" + str(row.index))
			if mission_id == 5: population._repair_roof_spawn(body)
			created.append(body)
		if created.is_empty(): return
	# Do not tag these as mission_owned: completion removes only mission actors.
	events[event] = true
	missions["world_events"] = events
