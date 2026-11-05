extends RefCounted
## Retail puffa/puffa2: 0046bbc0, fan 00455230, switch 0048a460.
class Switch extends StaticBody3D:
	var mission: RefCounted
	var collider: CollisionShape3D
	var meshes: Array[MeshInstance3D] = []
	func touching(player: RigidBody3D) -> bool:
		if global_position.distance_squared_to(player.global_position) > 9: return false
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = collider.shape; query.transform = collider.global_transform
		query.margin = 0.06; query.collision_mask = 2
		return get_world_3d().direct_space_state.intersect_shape(query,8).any(func(hit: Dictionary) -> bool: return hit.collider == player)
	func press(pressed: bool) -> void:
		for mesh in meshes: mesh.set_blend_shape_value(0,1.0 if pressed else 0.0)
	func take_weapon_damage(strength: float, _point: Vector3 = Vector3.ZERO) -> void:
		if mission != null and strength > 0: mission.switch_hit(true)

class Machinery extends Node3D:
	var controller: RefCounted
	func _physics_process(delta: float) -> void:
		if controller != null: controller._step_machinery(delta)
	func _exit_tree() -> void:
		if controller == null: return
		controller._restore_pipe()
		if is_instance_valid(controller.button): controller.button.mission = null
		controller = null

var jobs: Node
var outpost: RigidBody3D
var fan: Node3D
var button: StaticBody3D
var fish: Array[Node3D] = []
var enemies: Array[Node3D] = []
var turrets: Array[Node3D] = []
var blades: Array[StaticBody3D] = []
var fan_pose := Transform3D.IDENTITY
var current_pose := Transform3D.IDENTITY
var switch_pose := Transform3D.IDENTITY
var fan_speed := 0.0
var fan_direction := 1.0
var current_direction := 1.0
var switch_health := 10
var switch_touching := false
var switch_cooldown := 0.0
var elapsed := 0.0
var warned := false
var taunt_at := -1.0
var victory_at := -1.0
var resolved := false
var helper: RefCounted
var bubbles: Node3D
var pipe_gate: Node3D
var gate_visible := true
var gate_collisions: Array[Dictionary] = []
var machinery_retained := false

func start() -> void:
	jobs.phase = "stockpile"
	_open_pipe()
	helper = preload("res://student_rescue.gd").new(); helper.jobs = jobs
	for row in jobs._rows(42):
		var pose: Transform3D = jobs._pose(row)
		match int(row.ObjectID):
			1:
				outpost = helper.prop("PIRATEO",pose,40,0.2,1,false)
				outpost.freeze = true; outpost.destroyed.connect(_destroyed); jobs.target = outpost
				var creatures := preload("res://stage_two_remaining.gd").new(); creatures.jobs = jobs
				for index in range(9):
					var point := pose.origin+Vector3(randf_range(-1.5,1.5),randf_range(0.8,3.8),randf_range(-1.5,1.5))
					var robot: Node3D = creatures._fish("BLOWFISH",point,10,0.3,false,preload("res://fishbot.gd"))
					if robot != null:
						robot.ignore_wildlife = true; robot.traffic = jobs.game.submarine_traffic
						var no_blood: Array[Texture2D] = []
						robot.death_sound = null; robot.death_frames = no_blood; robot.death_flesh_texture = null
						fish.append(robot)
			2: current_pose = pose
			3: fan_pose = pose
			4: switch_pose = pose
			5:
				var pirate: Node3D = jobs._boat("PIRATE",pose,3,30)
				if pirate != null: pirate.engage_player = true; enemies.append(pirate)
			6:
				var model: Node3D = jobs.Document.load_model("TURRET",jobs.game.game_folder)
				jobs.game.world_root.add_child(model); model.global_transform = pose; jobs.actors.append(model)
				var body := StaticBody3D.new(); body.name = "SceneryCollision"; model.add_child(body)
				var gun: Node3D = preload("res://gun_turret.gd").install(model,{"turret_health":10,"turret_sustain":0.3,"turret_armed":true})
				gun.player = jobs.game.pilot; gun.bubble_trail = jobs.game.submarine_traffic.bubbles
				gun.bubble_texture = jobs.game.submarine_traffic.bubble_texture
				gun.explosion_frames = jobs.game.submarine_traffic.explosion_frames; gun.explosion_sound = jobs.game.submarine_traffic.explosion_sound
				gun.missile_template = jobs.Document.load_model("MISSILE",jobs.game.game_folder)
				gun.add_child(gun.missile_template); gun.missile_template.hide(); turrets.append(gun)
				jobs.game.natural_light.attach(model); jobs.game.water_visuals.attach(model)
	_build_fan()
	bubbles = preload("res://propeller_bubbles.gd").new(); jobs.game.world_root.add_child(bubbles); jobs.actors.append(bubbles)
	# The encounter advances this emitter explicitly in step().
	bubbles.set_physics_process(false)
	bubbles.configure(jobs.game.submarine_traffic.bubble_texture); bubbles.surface_height = jobs.game.pilot.surface_height

func _build_fan() -> void:
	fan = Node3D.new(); jobs.game.world_root.add_child(fan); fan.global_transform = fan_pose; jobs.actors.append(fan)
	for index in range(3):
		var blade := StaticBody3D.new(); fan.add_child(blade)
		blade.rotation.z = index*TAU/3.0
		var visual: Node3D = jobs.Document.load_model("FANBLADE",jobs.game.game_folder)
		blade.add_child(visual); visual.position.y = 2.1
		blade.set_meta("contact_inflict",0.5)
		for mesh in visual.find_children("*","MeshInstance3D",true,false):
			var shape := CollisionShape3D.new(); shape.shape = mesh.mesh.create_trimesh_shape()
			shape.shape.backface_collision = true
			shape.transform = blade.global_transform.affine_inverse()*mesh.global_transform; blade.add_child(shape)
		blades.append(blade)
	jobs.game.natural_light.attach(fan); jobs.game.water_visuals.attach(fan)
	button = Switch.new(); button.mission = self; jobs.game.world_root.add_child(button)
	button.global_transform = switch_pose; jobs.actors.append(button)
	var visual: Node3D = jobs.Document.load_model("SWITCH",jobs.game.game_folder,true); button.add_child(visual)
	var shape := CollisionShape3D.new(); shape.shape = preload("res://model_hitbox.gd").fitted_hull(visual); button.add_child(shape)
	button.collider = shape; preload("res://morph_animation.gd").collect(visual,button.meshes)
	jobs.game.natural_light.attach(button); jobs.game.water_visuals.attach(button)

func switch_hit(weapon: bool = false) -> void:
	if switch_cooldown > 0: return
	switch_cooldown = 0.4
	button.press(true)
	current_direction *= -1
	if switch_health > 0:
		fan_direction *= -1
		if weapon: switch_health -= 2
		if switch_health == 0:
			jobs.burst(button.global_position,0.5); jobs.burst(button.global_position,0.5)
			# Original broken switch stops issuing fan commands, but its contacts
			# can still reverse the current.
			button.get_child(0).hide()

func step(delta: float) -> void:
	elapsed += delta
	_step_machinery(delta)
	var player: RigidBody3D = jobs.game.pilot
	if not resolved: bubbles.emit_from(0,outpost.global_position+Vector3.UP*0.8,Vector3.UP,1,0.8,delta)
	bubbles.advance(delta)
	if not resolved and not warned and player.global_position.distance_to(outpost.global_position) < 16:
		warned = true; jobs.radio("ap1"); taunt_at = elapsed+12
	if taunt_at >= 0 and elapsed >= taunt_at: taunt_at = -1; jobs.radio("ap2")
	if victory_at >= 0 and elapsed >= victory_at:
		victory_at = -1; jobs.radio("ap3",true); jobs._resolve(true,1,1)

func _step_machinery(delta: float) -> void:
	switch_cooldown = maxf(0,switch_cooldown-delta)
	button.press(switch_cooldown > 0)
	fan_speed = move_toward(fan_speed,fan_direction*16,0.25*25*delta)
	fan.rotate_object_local(Vector3.FORWARD,deg_to_rad(fan_speed*25*delta))
	for blade in blades: blade.constant_angular_velocity = -fan.global_basis.z.normalized()*deg_to_rad(fan_speed*25)
	var player: RigidBody3D = jobs.game.pilot
	var touching: bool = button.touching(player)
	if touching and not switch_touching: switch_hit()
	switch_touching = touching
	_apply_current(delta)

func _apply_current(delta: float) -> void:
	var player: RigidBody3D = jobs.game.pilot
	if not player.active or player.dead or player.freeze: return
	var distance := player.global_position.distance_to(current_pose.origin)
	if distance >= 11: return
	# The player copies physical velocity into movement on every integration.
	# Its custom integrator also skips ordinary forces: deliver a timestep-scaled
	# impulse, like towing, rather than editing the discarded movement scratchpad.
	var impulse := current_pose.basis.z.normalized()*current_direction*10.0*(1.0-distance/11.0)*delta
	player.apply_central_impulse(impulse*preload("res://movement_model.gd").REFERENCE_MASS)

func _destroyed() -> void:
	if resolved: return
	resolved = true; victory_at = elapsed+2; taunt_at = -1
	var effect := preload("res://base_destruction.gd").new(); jobs.game.world_root.add_child(effect)
	effect.setup_vessel(outpost,jobs.game.submarine_traffic); outpost.hide(); outpost.set_deferred("collision_layer",0)

func target_body() -> CollisionObject3D:
	return outpost if is_instance_valid(outpost) and not outpost.dead else null

func release_survivors(success: bool = false) -> void:
	preload("res://mission_survivors.gd").release(jobs,enemies)
	if not success or machinery_retained: return
	var retained := Machinery.new(); retained.name = "StockpileMachinery"; retained.controller = self
	jobs.game.world_root.add_child(retained)
	fan.reparent(retained); button.reparent(retained)
	jobs.actors.erase(fan); jobs.actors.erase(button)
	machinery_retained = true
	jobs.runtime.retain_scene_until_docking(retained)
	for robot in fish:
		if is_instance_valid(robot) and not robot.dead:
			jobs.actors.erase(robot)
			jobs.runtime.retain_scene_until_docking(robot)
	for gun in turrets:
		if is_instance_valid(gun) and not gun.dead:
			var mount := gun.get_parent() as Node3D
			jobs.actors.erase(mount)
			jobs.runtime.retain_scene_until_docking(mount)

func clear() -> void:
	if not machinery_retained: _restore_pipe()
	if is_instance_valid(outpost) and outpost.destroyed.is_connected(_destroyed): outpost.destroyed.disconnect(_destroyed)
	if not machinery_retained and is_instance_valid(button): button.mission = null
	helper = null

func _open_pipe() -> void:
	# Retail0046bbc0 removes startup grating index1 (DAT_0089a4c0),
	# restoring it on encounter cleanup. Startup0042b9d0 indexes param2.
	for row in jobs.game.gameplay_catalogue.tables.get("database.objects",{}).get("records",{}).values():
		if int(row.get("MissionID",0)) != 2 or int(row.get("ObjectID",0)) != 5 or int(row.get("param2",-1)) != 1: continue
		pipe_gate = jobs.game.world_root.get_node_or_null("Scenery/PIPEBARS_%d" % int(row.index))
		if pipe_gate == null: return # Respect authored maps that omit this grille.
		gate_visible = pipe_gate.visible; pipe_gate.hide()
		for body in pipe_gate.find_children("*","CollisionObject3D",true,false):
			gate_collisions.append({"body":weakref(body),"layer":body.collision_layer,"mask":body.collision_mask})
			body.collision_layer = 0; body.collision_mask = 0
		return

func _restore_pipe() -> void:
	if is_instance_valid(pipe_gate): pipe_gate.visible = gate_visible
	for entry in gate_collisions:
		var body: CollisionObject3D = entry.body.get_ref()
		if body != null: body.collision_layer = entry.layer; body.collision_mask = entry.mask
	gate_collisions.clear(); pipe_gate = null
