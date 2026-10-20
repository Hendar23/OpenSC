extends RefCounted
## Retail 0046ae40 -> 00438360 -> 0041a1e0: once-only, unowned bonus objects.
const OPENING_BONUS := "opening_bonus"
const GROUP := "campaign/opening_bonus"

static func restore_for_progress(game: Node) -> void:
	# Published betas removed these objects on completion. Seed missing world
	# resources once for an existing post-opening save, independent of mail.
	var missions: Dictionary = game.player_progress.missions
	var started := int(game.player_progress.campaign_stage) > 1
	for id in ["tradetrad","tradetrad2","tradetech","tradetech2"]:
		started = started or missions.completed.has(id) or str(missions.active.get("id","")) == id
	if started: spawn_opening_bonus(game)

static func spawn_opening_bonus(game: Node) -> void:
	var missions: Dictionary = game.player_progress.missions
	var events: Dictionary = missions.get("world_events",{}) if missions.get("world_events",{}) is Dictionary else {}
	if events.get(OPENING_BONUS,false) == true: return
	var population: Node = game.object_population
	var existing := false
	for body in population.get_children():
		if body.get_meta("object_group","") == GROUP or str(body.get_meta("source_entity_id","")).begins_with(GROUP + "/"):
			existing = true; break
	if not existing:
		var definitions = preload("res://object_definitions.gd")
		var offset: Vector3 = game.world_root.get_meta("database_offset",Vector3.ZERO)
		var created: Array[Node] = []
		for row in game.gameplay_catalogue.tables.get("database.objects",{}).get("records",{}).values():
			if int(row.get("MissionID",0)) != 33 or int(row.get("AutoCreate",0)) != 1: continue
			var definition := {}
			match int(row.get("ObjectType",0)):
				64: definition = population.thorium_types.get("inert_thorium",definitions.inert_thorium(population.thorium_types.get("thorium",definitions.THORIUM)))
				86: definition = population.salvage_types.get("bottletop",definitions.SALVAGE)
			if definition.is_empty(): continue
			var pose := preload("res://scenery_loader.gd").placement(row,offset)
			var body: Node = population._create_thorium(definition,0,pose)
			if body == null:
				for node in created: node.free()
				return
			body.set_meta("object_group",GROUP)
			preload("res://entity_identity.gd").assign_id(body,GROUP + "/" + str(row.index))
			created.append(body)
		if created.is_empty(): return
	# Do not tag these as mission_owned: completion removes only mission actors.
	events[OPENING_BONUS] = true
	missions["world_events"] = events
