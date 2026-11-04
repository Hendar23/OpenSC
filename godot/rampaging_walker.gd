extends RefCounted
## Retail PWALKER mission 0042dc10 and walker controller 00463b70.
class Ally extends "res://mission_vessel.gd":
	func _react_to_damage(source: Vector3) -> void:
		if is_instance_valid(damage_attacker) and damage_attacker == system.player: super._react_to_damage(source)

var jobs: Node
var walker: RigidBody3D
var minelayers: Array[Node3D] = []
var allies: Array[Node3D] = []
var mines: Array[Node3D] = []
var points := {}
var route := {}
var waypoint := 0
var elapsed := 0.0
var mine_clock := 0.4
var begun := false
var resolved := false
var city_attacked := false
var city_clock := -1.0
var victory_clock := -1.0
var taunt_clock := 6.0
var target_clock := 0.0
var player_turn := false
var city_target: Node3D
var builder: RefCounted
var animation: RefCounted
var armament: Node3D
var head_visual: Node3D
var anchor_mesh: MeshInstance3D
var anchor_base := Vector3.ZERO
var anchor_poses: Array = []
var head_anchor := Vector3.ZERO
var foot_height := 0.0
var gait_distance := 0.0
var gait_stride := 1.0

func start() -> void:
	jobs.phase = "rendezvous"
	builder = preload("res://genocide_weapon.gd").new(); builder.jobs = jobs
	for row in jobs._rows(4):
		var index := int(row.get("param1",0))
		if int(row.ObjectID) == 3: points[index] = jobs._pose(row).origin
		if int(row.ObjectID) == 5: route[index] = jobs._pose(row).origin
		if int(row.ObjectID) == 6:
			city_target = Node3D.new(); jobs.game.world_root.add_child(city_target); city_target.global_transform = jobs._pose(row); jobs.actors.append(city_target)
	for row in jobs._rows(4):
		match int(row.ObjectID):
			1:
				walker = builder._cargo("PWALKER",jobs._pose(row),false,true)
				walker.health = 300; walker.damage_sustain = 0.1
				walker.set_meta("metal_tow_target",false); walker.weapon_hit.connect(_hit)
				animation = preload("res://creature_animation.gd").new(walker.appearance)
				anchor_mesh = walker.appearance.find_children("*","MeshInstance3D",true,false)[0]
				anchor_base = anchor_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][5]
				anchor_poses = anchor_mesh.mesh.surface_get_blend_shape_arrays(0)
				_measure_stride()
				foot_height = -preload("res://submarine_equipment.gd")._bounds(preload("res://submarine_equipment.gd")._meshes(walker.appearance,Transform3D.IDENTITY)).position.y
				var head: Node3D = jobs.Document.load_model("WALKHEAD",jobs.game.game_folder)
				if head != null:
					walker.appearance.add_child(head)
					head_visual = head
					var head_mesh: MeshInstance3D = head.find_children("*","MeshInstance3D",true,false)[0]
					head_anchor = head_mesh.transform*head_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0]
					_head_pose()
					jobs.game.natural_light.attach(head); jobs.game.water_visuals.attach(head)
					for mesh in head.find_children("*","MeshInstance3D",true,false):
						var collider := CollisionShape3D.new(); collider.shape = mesh.mesh.create_trimesh_shape(); collider.transform = walker.global_transform.affine_inverse()*mesh.global_transform
						collider.set_meta("walker_visual",weakref(mesh)); walker.add_child(collider)
					armament = preload("res://walker_armament.gd").new(); walker.add_child(armament); armament.setup(walker,jobs.game,head)
				builder._mark(walker)
			2:
				var ship: Node3D = jobs._boat("TRADHERD",jobs._pose(row),1,6,2.0,Ally)
				if ship == null: continue
				ship.combat_enabled = false; ship.dormant = true
				ship.destroyed.connect(_ship_dead.bind("d6")); minelayers.append(ship)
				ship.arrived.connect(_retreat.bind(ship,false)); ship.hull_damaged.connect(_minelayer_hit.bind(ship))
			4:
				var faction := 2 if int(row.param1) % 2 else 1
				var ship: Node3D = jobs._boat("TECH-SUB" if faction == 2 else "TRAD-SUB",jobs._pose(row),faction,3,2.0,Ally)
				if ship == null: continue
				ship.dormant = true; ship.destroyed.connect(_ship_dead.bind("d4" if faction == 2 else "d5")); allies.append(ship)
	jobs.target = walker

func _hit(strength: float, _source: Vector3, _attacker: Node3D, _kind: String, _head: bool) -> void:
	if resolved: return
	walker.health -= strength*0.1
	# Retail checks every eight seconds: minelayers prevent premature victory.
	if walker.health <= 0: _destroyed()

func _ship_dead(_entity: String, _attacker: String, code: String) -> void:
	if not resolved: target_clock = 0; jobs.radio(code)

func _minelayer_hit(_attacker: Node3D, ship: Node3D) -> void:
	if not ship.dead and ship.health.remaining <= 1.5: _retreat(ship,true)

func _retreat(ship: Node3D, damaged: bool) -> void:
	if resolved or ship.dead or ship.retiring: return
	jobs.radio("d3" if damaged else "d2"); target_clock = 0
	preload("res://mission_survivors.gd").depart(jobs,ship)

func step(delta: float) -> void:
	if resolved:
		if victory_clock >= 0:
			victory_clock -= delta
			if victory_clock <= 0: victory_clock = -1; jobs.radio("d11",true); jobs._resolve(true,1,1)
		return
	elapsed += delta
	if not begun:
		if elapsed < 4 or walker.global_position.distance_to(jobs.game.pilot.global_position) > _battle_range(): return
		begun = true; jobs.phase = "battle"; jobs.radio("d1")
		for index in minelayers.size():
			var ship: Node3D = minelayers[index]; ship.dormant = false
			for key in ([0,2,3] if index == 0 else [1,2,3]): ship.waypoints.append(points[key])
		for ship in allies: ship.dormant = false; ship.combat_target = walker; ship.pursue_offscreen = true
	if int((elapsed-delta)/8) != int(elapsed/8) and minelayers.any(func(ship: Node3D) -> bool: return is_instance_valid(ship) and not ship.dead): walker.health = maxf(walker.health,198.0)
	mine_clock -= delta
	if mine_clock <= 0:
		mine_clock = randf_range(32.0/25.0,95.0/25.0)
		for ship in minelayers:
			if not is_instance_valid(ship) or ship.dead or ship.retiring: continue
			_mine(ship.global_position-ship.get_parent().global_basis.z*0.5-Vector3.UP*0.2)
	for mine in mines:
		if is_instance_valid(mine) and not mine.dead and mine.global_position.distance_to(walker.global_position) < 1.1:
			mine.detonate(); _hit(17.5,Vector3.ZERO,null,"",false)
	if resolved: return
	if waypoint < route.size():
		var destination: Vector3 = route[waypoint]
		var offset := destination-walker.global_position
		var travel := minf(0.5*delta,Vector2(offset.x,offset.z).length())
		if Vector2(offset.x,offset.z).length() < 0.2:
			waypoint += 1
			if waypoint == route.size(): city_attacked = true; jobs.radio("d12"); city_clock = 8
		else:
			var heading := Vector3(offset.x,0,offset.z).normalized()
			walker.global_position += heading*travel
			walker.global_basis = walker.global_basis.orthonormalized().slerp(Basis.looking_at(-heading,Vector3.UP),minf(1,delta*0.3)).orthonormalized()
			var ray := PhysicsRayQueryParameters3D.create(walker.global_position+Vector3.UP*3,walker.global_position+Vector3.DOWN*5,1,[walker.get_rid()]); ray.hit_back_faces = true
			var ground: Dictionary = jobs.game.get_world_3d().direct_space_state.intersect_ray(ray)
			if not ground.is_empty(): walker.global_position.y = ground.position.y+foot_height
			_advance_gait(travel); _head_pose()
	if city_clock >= 0:
		city_clock -= delta
		if city_clock <= 0:
			city_clock = -1; jobs.radio("d13")
			var smoke := preload("res://smoke_emitter.gd").new(); jobs.game.world_root.add_child(smoke); jobs.actors.append(smoke)
			smoke.global_position = city_target.global_position; smoke.configure(jobs.game.game_folder,{})
	target_clock -= delta; taunt_clock -= delta
	if target_clock <= 0:
		target_clock = 12.0 if player_turn else 6.0; player_turn = not player_turn
		var victim: Node3D = null
		for ship in minelayers:
			if is_instance_valid(ship) and not ship.dead and not ship.retiring: victim = ship.body; break
		if victim == null:
			for ship in allies:
				if is_instance_valid(ship) and not ship.dead and not ship.retiring: victim = ship.body; break
			if player_turn or victim == null: victim = jobs.game.pilot
		if city_attacked and not player_turn: victim = city_target
		if armament != null: armament.target_override = victim
	if taunt_clock <= 0:
		taunt_clock = 30.0
		jobs.radio("d7" if minelayers.any(func(ship: Node3D) -> bool: return not ship.dead and not ship.retiring) else "d8" if allies.any(func(ship: Node3D) -> bool: return not ship.dead) else "d9")

func _mine(point: Vector3) -> void:
	var definition := preload("res://object_definitions.gd").FLOATING_MINE.duplicate(true)
	var mine := preload("res://floating_mine.gd").new()
	mine.setup(definition,jobs.game.object_population.appearance(definition,jobs.game.game_folder),jobs.game.submarine_traffic.explosion_sound,true)
	jobs.game.world_root.add_child(mine); jobs.actors.append(mine); mines.append(mine)
	mine.global_position = point; mine.home = point; mine.player = jobs.game.pilot
	mine.explosion_frames.assign(jobs.game.object_population.explosion_frames)
	mine.exploded.connect(jobs.game.object_population._exploded.bind(600.0))

func _destroyed() -> void:
	resolved = true; walker.dead = true; walker.hide(); walker.collision_layer = 0
	if armament != null: armament.set_physics_process(false)
	jobs.burst(walker.global_position,3.0); jobs.radio("d10",true); victory_clock = 8.0
	# Retail releases an intact WALKERHEAD with .2 shields, rather than
	# turning the head into a second set of chassis fragments.
	if is_instance_valid(head_visual):
		var salvage := preload("res://student_rescue.gd").new(); salvage.jobs = jobs
		var head: RigidBody3D = salvage.prop("WALKHEAD",head_visual.global_transform,0.2,0.1,5.0,true)
		if head != null:
			head.linear_velocity = Vector3.UP*0.3
			jobs.actors.erase(head); jobs.runtime.retain_prop_until_docking(head)
		head_visual.set_meta("exclude_from_debris",true)
	var wreck := preload("res://submarine_death.gd").new(); jobs.game.world_root.add_child(wreck); wreck.global_transform = walker.global_transform
	wreck.setup_machine(walker,walker.appearance,jobs.game.submarine_traffic.bubble_texture)

func release_survivors() -> void:
	for ship in minelayers+allies:
		if is_instance_valid(ship) and not ship.dead: preload("res://mission_survivors.gd").depart(jobs,ship)

func clear() -> void:
	resolved = true
	for ship in minelayers+allies:
		if not is_instance_valid(ship): continue
		for signal_name in ["destroyed","arrived","hull_damaged"]:
			for connection in ship.get_signal_connection_list(signal_name):
				if connection.callable.get_object() == self: ship.disconnect(signal_name,connection.callable)
	if is_instance_valid(walker) and walker.weapon_hit.is_connected(_hit): walker.weapon_hit.disconnect(_hit)
	builder = null

func target_body() -> CollisionObject3D:
	return walker if is_instance_valid(walker) and not resolved else null

func _measure_stride() -> void:
	# Retail 00463b70 translates the chassis to keep the planted foot fixed,
	# using PWALKER vertices110/69. Measure that same net travel over its eight
	# supplied poses, rather than running the generic creature preview at25Hz.
	var poses: Array = [anchor_mesh.mesh.surface_get_arrays(0)] + anchor_poses
	var advance := 0.0
	for index in poses.size():
		var before: PackedVector3Array = poses[index][Mesh.ARRAY_VERTEX]
		var after: PackedVector3Array = poses[(index+1)%poses.size()][Mesh.ARRAY_VERTEX]
		var foot := 110 if before[110].y+after[110].y < before[69].y+after[69].y else 69
		advance += (anchor_mesh.basis*(before[foot]-after[foot])).z
	gait_stride = maxf(0.001,absf(advance))

func _advance_gait(distance: float) -> void:
	gait_distance += distance
	# Morph.apply advances two poses per unit of time. One measured stride
	# completes the full cycle; stopping the chassis also stops the feet.
	animation.apply(gait_distance*float(anchor_poses.size()+1)/(2.0*gait_stride))

func _head_pose() -> void:
	if not is_instance_valid(head_visual): return
	var anchor := anchor_base
	for index in anchor_poses.size(): anchor += (anchor_poses[index][Mesh.ARRAY_VERTEX][5]-anchor_base)*anchor_mesh.get_blend_shape_value(index)
	anchor = anchor_mesh.transform*anchor
	head_visual.position = Vector3(0,anchor.y-head_anchor.y,anchor.z-1.0)

func _battle_range() -> float:
	# Begin beyond the extended view range, giving the allies time to get
	# underway before the player can see their original rendezvous formation.
	var camera: Camera3D = jobs.game.camera
	return maxf(20.0,camera.far+10.0) if is_instance_valid(camera) else 20.0
