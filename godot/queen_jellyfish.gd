extends RefCounted
## Retail aliens/aliens2 0043e5e0; egg fields 0043f1f0.
const Jelly = preload("res://nursery_jelly.gd")
const Prop = preload("res://mission_prop.gd")
var jobs: Node
var queen: Node3D
var fish: Array[Node3D] = []
var eggs: Array[Node3D] = []
var tethers: Array[Dictionary] = []
var guard: Node3D
var warned := false
var enraged := false
var resolved := false
var poll_clock := 0.0
var builder: RefCounted
var helper: RefCounted
var chain_template: Node3D
var chain_bounds: AABB
var rng := RandomNumberGenerator.new()

func start() -> void:
	jobs.phase = "nursery"; rng.randomize()
	builder = preload("res://student_rescue.gd").new(); builder.jobs = jobs
	helper = preload("res://stage_two_remaining.gd").new(); helper.jobs = jobs
	chain_template = jobs.Document.load_model("CHAIN",jobs.game.game_folder,true)
	if chain_template != null: chain_bounds = preload("res://submarine_equipment.gd")._bounds(preload("res://submarine_equipment.gd")._meshes(chain_template,Transform3D.IDENTITY))
	for row in jobs._rows(17):
		var pose: Transform3D = jobs._pose(row)
		match int(row.ObjectID):
			1:
				queen = _fish("MOMJELLY",pose.origin,0.05,2.5)
				if queen == null: continue
				queen.queen = true; queen.queen_held = true; queen.damage_sustain = 0; jobs.target = queen
				queen.combat.settings.merge({"zapper_aim_target":true,"zapper_start":1.0,"zapper_range":4.0},true)
				queen.died.connect(_queen_dead)
				var offsets := [Vector3(-1.5,0.5,0),Vector3(0,0.5,1.5),Vector3(1.5,0.5,0)]
				for index in range(3):
					var ship: RigidBody3D = builder.prop("TRAD-SUB",Transform3D(Basis.IDENTITY,queen.global_position+offsets[index]),10,0.3,25.0,false)
					if ship == null: continue
					builder.place_clear(ship)
					ship.set_meta("faction",1); ship.set_physics_process(true)
					ship.destroyed.connect(_tether_broken.bind(ship))
					var link: Node3D = chain_template.duplicate() if chain_template != null else Node3D.new()
					for mesh in link.find_children("*","MeshInstance3D",true,false):
						for blend in range(mesh.mesh.get_blend_shape_count()): mesh.set_blend_shape_value(blend,1.0 if blend == mesh.mesh.get_blend_shape_count()-1 else 0.0)
					jobs.game.world_root.add_child(link); jobs.actors.append(link)
					jobs.game.natural_light.attach(link); jobs.game.water_visuals.attach(link)
					tethers.append({"ship":ship,"link":link,"offset":offsets[index]})
				_eggs(pose.origin,6,5)
			2:
				var counts: Array = [[3,2,0],[2,2,1],[3,1,1],[4,0,1],[5,0,0]][clampi(int(row.param1),0,4)]
				_eggs(pose.origin,counts[0],4)
				for index in range(counts[1]): _fish("KIDJELLY",_clear_point(pose.origin,2),0.8,1.0)
				for index in range(counts[2]): _fish("BADJELLY",_clear_point(pose.origin,2),0.3,1.0)
			3:
				guard = jobs._boat("TRAD-SUB",pose,1,10,2.5)
				if guard != null: jobs._place_vessel_clear(guard); guard.combat_enabled = false
			4:
				for index in range(8): _mine(_clear_point(pose.origin,4))

func _fish(model: String, point: Vector3, sustain: float, speed: float) -> Node3D:
	var actor: Node3D = helper._fish(model,point,10,sustain,false,Jelly)
	if actor == null: return null
	actor.player = jobs.game.pilot; actor.ignore_wildlife = true; actor.swim_speed = speed; actor.attack_range = 8
	actor.combat.settings.has_zapper = true; actor.combat.settings.zapper_range = 1.0; actor.combat.settings.bite_range = 0.5
	actor.combat.settings["zapper_chance"] = 64 if model == "KIDJELLY" else 192
	actor.global_position = _above_floor(actor.global_position,actor.radius)
	fish.append(actor); return actor

func _clear_point(center: Vector3, radius: float) -> Vector3:
	var point := center+Vector3(rng.randf_range(-radius,radius),rng.randf_range(-radius,radius),rng.randf_range(-radius,radius))
	var query := PhysicsRayQueryParameters3D.create(center,point,1); query.hit_back_faces = true
	var hit: Dictionary = jobs.game.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty(): point = center.lerp(hit.position,0.5)
	return _above_floor(point,0.2)

func _above_floor(point: Vector3, clearance: float) -> Vector3:
	var hit := _floor_contact(point)
	if not hit.is_empty(): point.y = maxf(point.y,float(hit.position.y)+clearance+0.1)
	return point

func _floor_contact(point: Vector3) -> Dictionary:
	# Ambient probes start at the sea surface, which finds a cave's roof.
	# Nursery objects must settle onto the floor below their authored marker.
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*0.05,point+Vector3.DOWN*30,1)
	var excluded: Array[RID] = []
	for actor in jobs.actors:
		if actor is CollisionObject3D: excluded.append(actor.get_rid())
	query.exclude = excluded; query.hit_back_faces = true
	return jobs.game.get_world_3d().direct_space_state.intersect_ray(query)

func _eggs(center: Vector3, count: int, radius: float) -> void:
	for index in range(count):
		var point := _clear_point(center,radius)
		var ground := _floor_contact(point)
		if not ground.is_empty(): point = Vector3(ground.position)+Vector3.UP*0.05
		var egg: RigidBody3D = builder.prop("JELLYEGG",Transform3D(Basis.IDENTITY,point),10,1.0,1.0,false)
		if egg == null: continue
		egg.freeze = true; eggs.append(egg); egg.destroyed.connect(_egg_broken.bind(egg))
		builder.place_clear(egg)

func _egg_broken(egg: Node3D) -> void:
	if resolved or jobs.id.is_empty(): return
	var visual: Node3D = jobs.Document.load_model("EGGBROKE",jobs.game.game_folder)
	if visual != null:
		jobs.game.world_root.add_child(visual); visual.global_transform = egg.global_transform; jobs.actors.append(visual)
		jobs.game.natural_light.attach(visual); jobs.game.water_visuals.attach(visual)
	egg.hide()
	# Retail (random & 5)==0: two out of eight bit combinations hatch a child.
	if rng.randi() & 5 == 0:
		var child := _fish("KIDJELLY",egg.global_position+Vector3.UP*0.3,0.8,1.0)
		if child != null: child.provoked = true

func _mine(point: Vector3) -> void:
	var definition: Dictionary = preload("res://object_definitions.gd").FLOATING_MINE.duplicate(true)
	definition.merge({"appearance":"model","model":"MINE"},true)
	var population: Node = jobs.game.object_population
	var mine := preload("res://floating_mine.gd").new()
	mine.setup(definition,population.appearance(definition,jobs.game.game_folder),null,true)
	jobs.game.world_root.add_child(mine); mine.global_position = point; mine.home = point; mine.player = jobs.game.pilot
	mine.explosion_frames.assign(population.explosion_frames); mine.exploded.connect(population._exploded.bind(600.0)); jobs.actors.append(mine)
	mine.set_meta("mission_owner",jobs.id); jobs.game.natural_light.attach(mine); jobs.game.water_visuals.attach(mine)

func step(delta: float) -> void:
	if resolved or not is_instance_valid(queen) or queen.dead: return
	var alive_tethers: Array[Dictionary] = tethers.filter(func(pair: Dictionary) -> bool: return is_instance_valid(pair.ship) and not pair.ship.dead)
	queen.queen_held = not alive_tethers.is_empty(); queen.damage_sustain = 0.0 if queen.queen_held else 0.05
	queen.prey = alive_tethers[0].ship if queen.queen_held else null
	for pair in tethers:
		if not is_instance_valid(pair.ship) or pair.ship.dead: pair.link.hide(); continue
		var start: Vector3 = queen.global_position+Vector3(pair.offset).normalized()*0.5
		var span: Vector3 = pair.ship.global_position-start
		if span.length() > 1.0:
			pair.ship.apply_central_force(-span.normalized()*(span.length()-1.0)*pair.ship.mass*8)
		if span.length() > 0.01 and chain_template != null:
			var basis := Basis(Quaternion(Vector3.UP,span.normalized())).scaled_local(Vector3(1,span.length()/maxf(0.01,chain_bounds.size.y),1))
			pair.link.global_transform = Transform3D(basis,start+span*0.5-basis*chain_bounds.get_center())
		if queen.provoked: pair.ship.set_physics_process(true)
	poll_clock -= delta
	if poll_clock > 0: return
	poll_clock = 0.2
	var player: Node3D = jobs.game.pilot
	if is_instance_valid(guard) and not guard.dead and guard.global_position.distance_to(player.global_position) < 9:
		if not warned: warned = true; jobs.radio("q1")
		guard.combat_enabled = true; guard.engage_player = true
	if queen.provoked or queen.global_position.distance_to(player.global_position) < 6:
		queen.provoked = true
		if not enraged: enraged = true; jobs.radio("q2")
	var lit: bool = jobs.game.equipment.lamp.visible
	for actor in fish:
		if not is_instance_valid(actor) or actor.dead: continue
		if lit and actor.global_position.distance_to(player.global_position) < 8: actor.provoked = true
		for projectile in jobs.game.equipment.support_tools.projectiles:
			if is_instance_valid(projectile) and projectile.get_script() == preload("res://illuminating_flare.gd") and actor.global_position.distance_to(projectile.global_position) < 8:
				actor.provoked = true; break

func _queen_dead() -> void:
	if resolved or jobs.id.is_empty(): return
	resolved = true
	for pair in tethers: pair.link.hide()
	jobs.radio("miss1",true); jobs._resolve(true,1.0,1)

func _tether_broken(ship: RigidBody3D) -> void:
	if resolved or jobs.id.is_empty(): return
	var wreck := preload("res://submarine_death.gd").new(); jobs.game.world_root.add_child(wreck); wreck.global_position = ship.global_position
	wreck.setup_machine(ship,ship.get_child(0),jobs.game.submarine_traffic.bubble_texture,[],ship.linear_velocity)
	ship.hide()

func target_body() -> CollisionObject3D:
	return queen if is_instance_valid(queen) and not queen.dead and not resolved else null

func release_survivors() -> void:
	var survivors: Array[Node3D] = []
	if is_instance_valid(guard): survivors.append(guard)
	preload("res://mission_survivors.gd").release(jobs,survivors)

func clear() -> void:
	resolved = true
	if is_instance_valid(queen) and queen.died.is_connected(_queen_dead): queen.died.disconnect(_queen_dead)
	for pair in tethers:
		var callback := _tether_broken.bind(pair.ship)
		if is_instance_valid(pair.ship) and pair.ship.destroyed.is_connected(callback): pair.ship.destroyed.disconnect(callback)
	for egg in eggs:
		var callback := _egg_broken.bind(egg)
		if is_instance_valid(egg) and egg.destroyed.is_connected(callback): egg.destroyed.disconnect(callback)
	if is_instance_valid(chain_template): chain_template.free()
	chain_template = null; builder = null; helper = null
