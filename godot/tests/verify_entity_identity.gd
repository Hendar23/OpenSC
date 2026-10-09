extends SceneTree
const Population = preload("res://object_population.gd")
const Definitions = preload("res://object_definitions.gd")
const Document = preload("res://map_document.gd")
const Identity = preload("res://entity_identity.gd")
const Clam = preload("res://clam.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func identities(entries: Array) -> Array:
	return entries.map(func(entry: Dictionary) -> Array: return [entry.get("entity_id",""),entry.get("object_group",""),entry.get("source_entity_id",""),entry.get("clam_state",{}).get("pearl_id","")])
func _initialize() -> void: call_deferred("run")
func run() -> void:
	check(Identity.valid(Identity.authored("long name".repeat(100),0)),"Long mod group names still produce bounded stable identities")
	preload("res://mod_registry.gd").initialize(false)
	var world := Node3D.new(); root.add_child(world)
	var population := Population.new(); world.add_child(population)
	var document := Document.empty(); Definitions.ensure(document)
	document.object_groups = [
		{"id":"crystals","name":"Crystals","type":"thorium","position":[0,2,0],"count":2,"radius":1},
		{"id":"shell","name":"Shell","type":"clam","position":[4,0,0],"count":1,"radius":0,"initial_delay":0}
	]
	population.setup(preload("res://asset_paths.gd").find_game_folder(),document,false)
	var snapshot := population.snapshot()
	var crystal: Node3D = population.get_children().filter(func(node: Node) -> bool: return node.get_meta("object_group","") == "crystals")[0]
	var clam: Clam = population.get_children().filter(func(node: Node) -> bool: return node is Clam)[0]
	check(Identity.of(crystal) == Identity.authored("crystals",0),"Authored identities use group and member, not node order")
	check(Identity.of(clam) == Identity.authored("shell",0),"Clams have authored identities")
	var pearl_id := Identity.of(clam.pearl)
	crystal.position += Vector3(3,0,0)
	var generated := population._create_thorium(Definitions.metal_types()[2],0,Transform3D.IDENTITY)
	var generated_id := Identity.of(generated)
	check(generated_id.begins_with("spawn/"),"Generated salvage gets an independent identity")
	snapshot = JSON.parse_string(JSON.stringify(population.snapshot()))
	check(Population.valid_snapshot(snapshot),"Identity-bearing snapshots survive JSON serialization")
	population.restore_snapshot(snapshot)
	var roundtrip := population.snapshot()
	check(identities(roundtrip) == identities(snapshot),"Object, group and pearl identities survive a full restore")
	check(Document.decode(roundtrip[0].pose).is_equal_approx(Document.decode(snapshot[0].pose)),"Moving an object does not change its identity on restore")
	clam = population.get_children().filter(func(node: Node) -> bool: return node is Clam)[0]
	check(Identity.of(clam.pearl) == pearl_id,"Nested pearl identity survives saving inside its clam")
	var pearl: RigidBody3D = clam.pearl
	clam.release_pearl()
	check(Identity.of(pearl) == pearl_id,"Extracting a pearl preserves its identity")
	clam._grow_pearl()
	check(Identity.of(clam.pearl) != pearl_id,"A regrown pearl is a distinct entity")
	population.restore_snapshot(population.snapshot())
	check(Population.valid_snapshot(population.snapshot()),"Extracted and regrown pearls can be saved together")
	crystal = population.get_children().filter(func(node: Node) -> bool: return node.get_meta("object_group","") == "crystals")[0]
	var original_id := Identity.of(crystal)
	population._shatter(crystal)
	await process_frame
	var shards: Array = population.snapshot().filter(func(entry: Dictionary) -> bool: return entry.get("source_entity_id","") == original_id)
	check(shards.size() == 3,"All shards retain the destroyed crystal's identity as their origin")
	var shard_ids: Array = shards.map(func(entry: Dictionary) -> String: return entry.entity_id)
	check(shard_ids.size() == 3 and shard_ids[0] != shard_ids[1] and shard_ids[1] != shard_ids[2] and shard_ids[0] != shard_ids[2] and not original_id in shard_ids,"Shards receive separate identities")
	snapshot = population.snapshot(); population.restore_snapshot(snapshot)
	check(identities(population.snapshot()) == identities(snapshot),"Shard origins survive restore")
	var invalid := snapshot.duplicate(true); invalid[1].entity_id = invalid[0].entity_id
	check(not Population.valid_snapshot(invalid),"Duplicate saved target identities are rejected")
	invalid = snapshot.duplicate(true); invalid[0].entity_id = 42
	check(not Population.valid_snapshot(invalid),"Non-string identities are rejected")
	invalid = snapshot.duplicate(true); invalid[0].entity_id = ""
	check(not Population.valid_snapshot(invalid),"Empty identities are rejected")
	var old := snapshot.duplicate(true)
	for entry in old:
		entry.erase("entity_id"); entry.erase("source_entity_id")
		if entry.has("clam_state"): entry.clam_state.erase("pearl_id")
	check(Population.valid_snapshot(old),"Saves from before entity IDs remain accepted")
	population.restore_snapshot(old)
	var migrated := population.snapshot()
	check(Population.valid_snapshot(migrated) and migrated.all(func(entry: Dictionary) -> bool: return Identity.valid(entry.entity_id)),"Old saves migrate to unique persistent identities")
	population.restore_snapshot(migrated)
	check(identities(population.snapshot()) == identities(migrated),"Migrated identities remain stable on later loads")
	# A partially migrated save must not collide with an explicit legacy ID.
	old[1].entity_id = "legacy/0"
	population.restore_snapshot(old)
	check(Population.valid_snapshot(population.snapshot()),"Mixed old and new identity records migrate without collisions")
	population.reset_population()
	check(population.snapshot() == population.initial_thorium,"New game resets authored identities and original object state")
	world.free()
	print("Entity identity: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
