extends RefCounted
## Original new-game mine forests (0x42b9d0 / 0x42b500), separate from mission mines.
const Mine = preload("res://floating_mine.gd")
const Document = preload("res://map_document.gd")
const Identity = preload("res://entity_identity.gd")
const FIELD_STEP := 10.0 / 16.0
const WORLD_ATTEMPTS := 11 # Type index 21 in the 300-iteration, 26-type startup loop.
var owner: Node3D
var definition := {}
var fields: Array[Dictionary] = []
var template: Node3D
var sound: AudioStream

func setup(population: Node3D, types: Dictionary) -> void:
	owner = population
	# Synthetic test worlds and previews without database coordinates have no original fields.
	if not owner.get_parent().has_meta("database_offset") or not types.has("floating_mine"): return
	definition = types.floating_mine.duplicate(true)
	var scenery = preload("res://scenery_loader.gd")
	var tables: Dictionary = scenery.read_database(owner.asset_folder.path_join("DATA/SCEN1.DDB"))
	for row in tables.get("Objects",[]):
		if int(row.get("MissionID",0)) != 2 or int(row.get("ObjectID",0)) != 28: continue
		var pose: Transform3D = scenery.placement(row,owner.get_parent().get_meta("database_offset"))
		if pose.origin.is_finite(): fields.append({"record":int(row.index),"center":pose.origin,"attempts":int(row.get("param2",0))})
	template = owner.appearance(definition,owner.asset_folder)
	if template != null and template.has_meta("trigger_distance"): definition.trigger_distance = float(template.get_meta("trigger_distance"))
	sound = preload("res://submarine_weapons.gd")._sound(owner.asset_folder,"audio.object.mine.explosion","EXPLODE1")

func close() -> void:
	if is_instance_valid(template): template.free()
	template = null

func clear_generated() -> void:
	for body in owner.get_children():
		if body is Mine and body.get_meta("startup_mine",false): body.free()

func field_candidate(center: Vector3) -> Vector3:
	return center + Vector3(int(owner.random.randi() & 31) - 16,int(owner.random.randi() & 31) - 16,int(owner.random.randi() & 31) - 16) * FIELD_STEP

func valid_field_point(point: Vector3) -> bool:
	if point.y >= owner.surface_height: return false
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x,owner.surface_height + 5.0,point.z),Vector3(point.x,owner.world_bounds.position.y - 5.0,point.z),1)
	query.hit_back_faces = true
	var hit := owner.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.position.y < point.y

func populate_startup() -> void:
	clear_generated()
	if template == null: return
	for field in fields:
		for attempt in range(field.attempts):
			var point := field_candidate(field.center)
			if valid_field_point(point): create(point,"startup-mine/field-%d/%d" % [field.record,attempt])
	for attempt in range(WORLD_ATTEMPTS):
		var result: Dictionary = owner._random_spawn_point(definition,true)
		if result.is_empty(): continue
		var point: Vector3 = result.position
		point.y += float(owner.random.randi() & 15) * 0.25
		if point.y < owner.surface_height: create(point,"startup-mine/world/%d" % attempt)

func create(point: Vector3, identity: String, health: float = -1.0, phase: float = -1.0, age: float = 0.0) -> Node3D:
	if template == null: return null
	var mine := Mine.new()
	mine.name = "StartupMine_%d" % owner.get_child_count()
	mine.setup(definition,template.duplicate(),sound,owner.simulating)
	owner.add_child(mine); Identity.assign_id(mine,identity)
	mine.set_meta("startup_mine",true)
	mine.home = point; mine.phase = owner.random.randf() * TAU if phase < 0.0 else phase
	mine.age = age; mine.position = point + Vector3.UP * sin(age * 1.4 + mine.phase) * minf(0.06,float(definition.size) * 0.06)
	mine.player = owner.player; mine.explosion_frames.assign(owner.explosion_frames)
	if health >= 0.0: mine.health = health
	mine.exploded.connect(owner._exploded.bind(float(definition.get("blast_force",600.0))))
	return mine

func snapshot() -> Array:
	var entries := []
	for body in owner.get_children():
		if body is Mine and body.get_meta("startup_mine",false) and not body.dead:
			entries.append({"entity_id":Identity.of(body),"home":Document.array(body.home),"health":body.health,"phase":body.phase,"age":body.age})
	return entries

static func valid_snapshot(entries: Variant) -> bool:
	if not entries is Array or entries.size() > 10000: return false
	var identities := {}
	for entry in entries:
		if not entry is Dictionary or not Identity.valid(entry.get("entity_id")) or identities.has(entry.entity_id): return false
		identities[entry.entity_id] = true
		if not Document.finite_array(entry.get("home"),3): return false
		for key in ["health","phase","age"]:
			if not preload("res://object_definitions.gd").numeric(entry.get(key),0,1000000000): return false
	return true

func restore(entries: Array) -> void:
	if not valid_snapshot(entries): return
	clear_generated()
	for entry in entries: create(Document.vector(entry.home),entry.entity_id,float(entry.health),float(entry.phase),float(entry.age))
