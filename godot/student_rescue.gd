extends RefCounted
## Retail miners/miners2 00430190, shared placement group 13.
const Prop = preload("res://mission_prop.gd")
static var clear_offsets: Array[Vector3] = []
var jobs: Node
var ship: RigidBody3D
var rock: RigidBody3D
var enemies: Array[Node3D] = []
var pirate_poses: Array[Transform3D] = []
var found := false
var attached := false
var loose_warned := false
var low_warned := false
var delivered := false
var poll_clock := 2.0

func start() -> void:
	jobs.phase = "search"
	for row in jobs._rows(13):
		var pose: Transform3D = jobs._pose(row)
		match int(row.ObjectID):
			1:
				# The row says TECHSHUT; the retail callback creates MINING.
				ship = prop("MINING",pose,500,0.3,25.0,true)
				if ship == null: continue
				place_clear(ship)
				ship.freeze = true; ship.release_on_tow = true
				ship.set_meta("metal_tow_target",true); ship.set_meta("mission_delivery",true); jobs.target = ship
				ship.destroyed.connect(_lost)
				var smoke := preload("res://submarine_damage_smoke.gd").new(); ship.add_child(smoke)
				smoke.setup(ship.get_child(0),jobs.game.game_folder); smoke.damaged = true; smoke.enabled = true
				_mark(ship)
			2:
				rock = prop("BIGROCK",pose,28.0,1.0,16.0,false)
				if rock != null: rock.freeze = true; rock.destroyed.connect(_rock_broken)
			3: pirate_poses.append(pose)
	if is_instance_valid(ship):
		for index in range(6):
			var pose := ship.global_transform
			pose.origin += Vector3(cos(index*TAU/6),-0.2,sin(index*TAU/6))*1.2
			prop("ROCK" if index < 2 else "SMALROCK",pose,2,1,1,false)
	if is_instance_valid(rock):
		for index in range(2):
			var pose := rock.global_transform; pose.origin += Vector3(index*0.4-0.2,0.1,0)
			prop("SMALROCK",pose,2,1,1,false)

func prop(model: String, pose: Transform3D, health: float, sustain: float, mass: float, metal: bool) -> RigidBody3D:
	var visual: Node3D = jobs.Document.load_model(model,jobs.game.game_folder)
	if visual == null: return null
	var definition: Dictionary = preload("res://object_definitions.gd").SALVAGE.duplicate(true)
	definition.merge({"id":"mission_prop","name":model,"model":model,"health":health,"mass":mass,"magnet_compatible":metal,"grapple_compatible":false,"suckomat_compatible":false,"delivery_commodity":"","delivery_quantity":0},true)
	var body := Prop.new(); body.sustain = sustain
	body.setup(definition,visual,0,jobs.game.pilot.surface_height,true)
	jobs.game.world_root.add_child(body); body.global_transform = pose; jobs.actors.append(body)
	body.set_meta("mission_owner",jobs.id); body.set_meta("damage_sustain",sustain)
	jobs.game.natural_light.attach(visual); jobs.game.water_visuals.attach(visual)
	return body

func place_clear(body: RigidBody3D) -> void:
	# Original sphere markers can put the recovered convex hull into a cave
	# wall. Find the nearest water that fits, without moving it out of the cave.
	var shape: CollisionShape3D = body.get_child(1)
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = shape.shape
	query.collision_mask = 1; query.exclude = [body.get_rid()]; query.margin = 0.02
	query.transform = body.global_transform*shape.transform
	if jobs.game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return
	if clear_offsets.is_empty():
		for lift in [0.0,0.15,0.3,0.5,0.75,1.0,1.5,2.0,-0.15,-0.3,-0.5]:
			for radius in [0.0,0.25,0.5,1.0,1.5,2.0]:
				for side in (1 if radius == 0 else 8):
					var angle := side*TAU/8.0
					clear_offsets.append(Vector3(cos(angle)*radius,lift,sin(angle)*radius))
		clear_offsets.sort_custom(func(a: Vector3,b: Vector3) -> bool: return a.length_squared() < b.length_squared())
	var origin := body.global_position
	for offset in clear_offsets:
		query.transform = Transform3D(body.global_basis,origin+offset)*shape.transform
		if not jobs.game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
		body.global_position = origin+offset; body.reset_physics_interpolation(); return

func _mark(body: Node3D) -> void:
	body.set_meta("faction",2); jobs.game.cockpit_hud.map_data.actor_markers.append(body)
	var meshes := preload("res://submarine_equipment.gd")._meshes(body.get_child(0),Transform3D.IDENTITY)
	body.set_meta("mission_target_center",preload("res://submarine_equipment.gd")._bounds(meshes).get_center())

func step(delta: float) -> void:
	if not is_instance_valid(ship) or ship.dead or delivered: return
	var towing: bool = jobs.game.equipment.magnet.target == ship
	if towing != attached:
		attached = towing
		if towing: jobs.radio("m3")
		elif found and not loose_warned and ship.health > 1: loose_warned = true; jobs.radio("m4")
	poll_clock -= delta
	if poll_clock > 0: return
	poll_clock = 2.0 if found else 1.2
	if not found and ship.global_position.distance_squared_to(jobs.game.pilot.global_position) < 25:
		found = true; ship.health = 5.0; ship.freeze = false; jobs.phase = "tow"; jobs.radio("m1")
		if is_instance_valid(rock):
			var helper := preload("res://stage_two_remaining.gd").new(); helper.jobs = jobs
			helper._fish("BADJELLY",rock.global_position,10,0.3,false)
		for pose in pirate_poses:
			var pirate: Node3D = jobs._boat("PIRATE",pose,3,10,2.5)
			if pirate == null: continue
			jobs._place_vessel_clear(pirate,true)
			pirate.engage_player = true; pirate.pursue_offscreen = true; enemies.append(pirate)
	if found and ship.health < 2 and not low_warned: low_warned = true; jobs.radio("m7")

func target_body() -> CollisionObject3D:
	if is_instance_valid(rock) and not rock.dead and not delivered: return rock
	return ship if is_instance_valid(ship) and not ship.dead and not delivered else null

func delivery(body: Node3D, city: int) -> bool:
	if body != ship or delivered or ship.dead: return false
	if city not in [2,4]: jobs.radio("m6"); jobs.game.equipment.magnet.decline_delivery(); return true
	delivered = true; ship.delivered = true; ship.set_meta("delivery_city",city)
	jobs.game.equipment.magnet.set_enabled(false)
	jobs.runtime.active()["resolved_city"] = city; jobs.radio("m5",true); jobs._resolve(true,1.0,1)
	return true

func _rock_broken() -> void:
	if not is_instance_valid(rock): return
	var pose: Transform3D = rock.global_transform; rock.hide()
	for index in range(2):
		var fragment := prop("SMALROCK",pose,2,1,1,false)
		if fragment != null: fragment.global_position += Vector3((index*2-1)*0.25,0.1,0); fragment.linear_velocity = Vector3((index*2-1)*0.4,0.3,0)

func _lost() -> void:
	if delivered or jobs.id.is_empty(): return
	var wreck := preload("res://submarine_death.gd").new(); jobs.game.world_root.add_child(wreck); wreck.global_position = ship.global_position
	wreck.setup_machine(ship,ship.get_child(0),jobs.game.submarine_traffic.bubble_texture,[],ship.linear_velocity)
	ship.hide(); jobs.radio("m2",true); jobs._resolve(false,0,2)

func release_survivors() -> void:
	preload("res://mission_survivors.gd").release(jobs,enemies)

func clear() -> void:
	for body in [ship,rock]:
		if is_instance_valid(body) and body.destroyed.is_connected(_lost): body.destroyed.disconnect(_lost)
	if is_instance_valid(rock) and rock.destroyed.is_connected(_rock_broken): rock.destroyed.disconnect(_rock_broken)
