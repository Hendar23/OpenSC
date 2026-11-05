extends RefCounted
## Released canister callback00491540; authored placement group41.
const Damage = preload("res://original_damage.gd")
const Survivors = preload("res://mission_survivors.gd")
const SEAL_DELAY := 59.2 # 100 + 5*260 + 80 original 25Hz ticks.
const CAVE_RADIATION := 0.013 * 8.0 # Mission balance adjustment to the original rate.

class Cloud extends "res://smoke_emitter.gd":
	func _process(delta: float) -> void:
		super._process(delta)
		if not enabled and puffs.is_empty(): queue_free()

class Cave extends Node3D:
	var stats := {"radiation_range":31.0}
	var dead := false
	var delivered := false
	var radioactive := false
	var folder := ""
	var explosion_frames: Array[Texture2D] = []
	var explosion_sound: AudioStream
	func configure_smoke(plume: Node3D, values: Dictionary) -> void:
		# Explosion preparation already owns the mod-aware smoke textures.
		# Reuse them when a canister breaks instead of decoding BMPs in combat.
		var textures: Array[Texture2D] = preload("res://mine_explosion.gd").smoke_frames
		if textures.is_empty(): plume.configure(folder,values); return
		plume.tuning.merge(values,true); plume.enabled = bool(values.get("enabled",true))
		plume.textures.assign(textures); plume.rng.randomize()
	func radiation_strength_at(_distance: float) -> float:
		return Damage.radiation_strength(CAVE_RADIATION) if radioactive else 0.0
	func canister_destroyed(body: Node3D) -> void:
		var point := body.global_position
		body.hide()
		var explosion := preload("res://mine_explosion.gd").new()
		get_parent().add_child(explosion)
		explosion.global_position = point
		explosion.setup(explosion_frames,3.0,explosion_sound)
		clouds(point,9)
	func clouds(point: Vector3, count: int) -> void:
		var cloud := Cloud.new(); add_child(cloud); cloud.global_position = point
		configure_smoke(cloud,{"enabled":false,"spread":0.5,"start_size":0.5,"end_size":2.0})
		for index in count:
			cloud._emit()
			cloud.puffs.back().node.global_position += Vector3(randf_range(-0.5,0.5),randf_range(-0.5,0.5),randf_range(-0.5,0.5))

var jobs: Node
var helper: RefCounted
var cave: Node3D
var canisters: Array[Node3D] = []
var allies: Array[Node3D] = []
var enemies: Array[Node3D] = []
var waypoints := PackedVector3Array()
var collapse_points := PackedVector3Array()
var seal_pose := Transform3D.IDENTITY
var charge_pose := Transform3D.IDENTITY
var guard_pose := Transform3D.IDENTITY
var charge: Node3D
var plug: RigidBody3D
var smoke: Array[Node3D] = []
var elapsed := 0.0
var approach_at := -1.0
var first_destroyed_at := -1.0
var remaining := 6
var sealed := false
var escaped := false
var finished := false
var warned := false
var announced := false
var setting_charges := false
var urgency := false
var warning := 0

func start() -> void:
	jobs.phase = "stockpile"
	helper = preload("res://student_rescue.gd").new(); helper.jobs = jobs
	cave = Cave.new(); cave.name = "NuclearCave"
	jobs.game.world_root.add_child(cave); jobs.actors.append(cave)
	cave.folder = jobs.game.game_folder
	cave.explosion_frames = jobs.game.submarine_traffic.explosion_frames
	cave.explosion_sound = jobs.game.submarine_traffic.explosion_sound
	cave.add_to_group("mission_radiation_sources")
	allies.resize(3); canisters.resize(6); waypoints.resize(3); collapse_points.resize(2)
	for row in jobs._rows(41):
		if int(row.ObjectID) == 7: cave.global_position = jobs._pose(row).origin
	for row in jobs._rows(41):
		var pose: Transform3D = jobs._pose(row)
		var index := int(row.get("param2",0))
		match int(row.ObjectID):
			1:
				# The database calls these PIRATE3; the callback creates PIRATE.
				var agent: Node3D = jobs._boat("PIRATE",pose,3,30,2.5)
				if agent != null:
					agent.engage_player = true; enemies.append(agent)
					jobs._place_vessel_clear(agent)
			2:
				var body: RigidBody3D = helper.prop("CANISTER",pose,10,0.5,10000,false)
				if body == null: continue
				body.freeze = true; body.towing_allowed = false
				body.stats.immovable = true
				body.reparent(cave,true); jobs.actors.erase(body); canisters[index] = body
				body.destroyed.connect(cave.canister_destroyed.bind(body))
				body.destroyed.connect(_canister_destroyed.bind(body))
			3:
				var agent: Node3D = jobs._boat("TRAD2" if index == 1 else "TRAD-SUB",pose,1,10)
				if agent != null:
					agent.combat_enabled = false; agent.health.sustain = 0
					allies[index] = agent; jobs._place_vessel_clear(agent)
			4: waypoints[index] = pose.origin
			5: seal_pose = pose
			6: collapse_points[index] = pose.origin
			8: charge_pose = pose
			9: guard_pose = pose
	charge = jobs.Document.load_model("MASSIVE",jobs.game.game_folder)
	if charge != null:
		cave.add_child(charge)
		if is_instance_valid(allies[1]): charge.global_position = allies[1].global_position+Vector3.DOWN
		jobs.game.natural_light.attach(charge); jobs.game.water_visuals.attach(charge)

func _canister_destroyed(_body: Node3D) -> void:
	if finished: return
	remaining -= 1
	if remaining == 5:
		first_destroyed_at = elapsed; jobs.phase = "escape"
		# Retail detaches the charge at marker8, and moves its carrier (ally1)
		# to marker9. The other two ships keep their original positions.
		if is_instance_valid(charge): charge.global_transform = charge_pose
		if is_instance_valid(allies[1]) and not allies[1].dead:
			allies[1].get_parent().global_transform = guard_pose
			jobs._place_vessel_clear(allies[1])
			allies[1].get_parent().reset_physics_interpolation()
		for size in [0.35,0.7]:
			var plume := preload("res://smoke_emitter.gd").new(); cave.add_child(plume)
			plume.global_position = charge_pose.origin
			cave.configure_smoke(plume,{"start_size":size}); smoke.append(plume)
	elif remaining == 0 and not sealed: jobs.radio("ao12")

func step(delta: float) -> void:
	if finished: return
	elapsed += delta
	if not announced and elapsed >= 8: announced = true; jobs.radio("ao9")
	if approach_at < 0 and elapsed >= 4:
		for point in waypoints:
			if point.distance_to(jobs.game.pilot.global_position) < 20:
				approach_at = elapsed+0.2; break
	if approach_at >= 0:
		if not warned and elapsed >= approach_at: warned = true; jobs.radio("ao11")
		if not setting_charges and elapsed >= approach_at+12: setting_charges = true; jobs.radio("ao10")
	if first_destroyed_at < 0: return
	var age := elapsed-first_destroyed_at
	if age >= 2: cave.radioactive = true
	while warning < 6 and age+0.00001 >= 4+float(warning)*10.4:
		jobs.radio("ao%d" % (warning+1)); warning += 1
	if not urgency and age >= 22: urgency = true; jobs.radio("ao13")
	if not sealed and age+0.00001 >= SEAL_DELAY:
		_seal()
		if finished: return
	if sealed and escaped and age+0.00001 >= SEAL_DELAY+14:
		finished = true
		if remaining == 0: jobs.radio("ao14",true)
		jobs._resolve(remaining == 0,1 if remaining == 0 else 0,1 if remaining == 0 else 0)

func _seal() -> void:
	sealed = true; jobs.phase = "sealed"
	escaped = cave.global_position.distance_to(jobs.game.pilot.global_position) > 31
	if is_instance_valid(charge): charge.queue_free(); charge = null
	for plume in smoke:
		if is_instance_valid(plume): plume.enabled = false
	plug = helper.prop("BIGROCK",seal_pose,1000000,0,10000,false)
	if plug != null:
		plug.freeze = true; plug.towing_allowed = false; plug.stats.immovable = true
		plug.reparent(cave,true); jobs.actors.erase(plug)
	for point in collapse_points:
		jobs.burst(point,3); cave.clouds(point,3)
		var debris := preload("res://submarine_death.gd").new()
		jobs.game.world_root.add_child(debris); debris.global_position = point
		var rock: Node3D = jobs.Document.load_model("SMALROCK",jobs.game.game_folder)
		if rock != null:
			debris.add_child(rock); debris.setup_machine(rock,rock,jobs.game.submarine_traffic.bubble_texture); rock.hide()
		else: debris.queue_free()
	# Retail sends the military team back toward its upper abyss waypoint.
	for ally in allies:
		if not is_instance_valid(ally) or ally.dead: continue
		ally.health.sustain = 0.3; ally.waypoints = PackedVector3Array([waypoints[0]])
		ally.path.clear(); ally.waypoint = 0
	if escaped: jobs.radio("ao8")
	else:
		jobs.radio("ao7",true); finished = true; jobs._resolve(false,0,0)

func target_body() -> CollisionObject3D:
	# The original clears guidance on the first destruction; no radar reveals
	# the remaining canisters hidden around the cave.
	return null

func release_survivors() -> void:
	# Preserve independent living ships, including the abort branch. Once the
	# operation has ended the team can retire through normal friendly docking.
	Survivors.release(jobs,enemies)
	for ally in allies:
		if not is_instance_valid(ally) or ally.dead: continue
		ally.health.sustain = 0.3
		Survivors.depart(jobs,ally)
	if sealed and is_instance_valid(cave):
		jobs.actors.erase(cave); jobs.runtime.retain_scene_until_docking(cave)

func clear() -> void:
	for body in canisters:
		if is_instance_valid(body) and body.destroyed.is_connected(_canister_destroyed.bind(body)):
			body.destroyed.disconnect(_canister_destroyed.bind(body))
	helper = null
