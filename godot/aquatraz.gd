extends RefCounted
## Retail0042f5f0 and city0044c610; placement group44.
const Survivors = preload("res://mission_survivors.gd")
const NORMAL_SPIN := deg_to_rad(25.0)
var jobs: Node
var site: Node3D
var factory: Node3D
var hull: StaticBody3D
var guns: Array[Node3D] = []
var allies: Array[Node3D] = []
var modulators: Array[Node3D] = []
var enemies: Array[Node3D] = []
var ground_guns: Array[Node3D] = []
var plasma: Array[Texture2D] = []
var shield: StaticBody3D
var shield_arcs: Array[Node3D] = []
var shield_flash := 0.0
var shield_clock := 1.2
var shield_left := Vector3.ZERO
var shield_right := Vector3.ZERO
var rotation_speed := NORMAL_SPIN
var age := 0.0
var deadline := 8.0
var reinforcement := -1.0
var spinup := false
var destroyed := false
var resolved := false
var retained := false
var factory_pose := Transform3D.IDENTITY
var bay := 0.0

func start() -> void:
	jobs.phase = "rendezvous"
	site = preload("res://mission_site.gd").new(); site.name = "AquatrazBattle"
	jobs.game.world_root.add_child(site); jobs.actors.append(site)
	var city: Node3D = jobs.game.submarine_traffic.port_by_id(5).get("node")
	factory_pose = city.global_transform
	site.mask(city); city.set_meta("mission_dock_disabled",true)
	if not city.has_meta("aquatraz_restore_state"): city.set_meta("aquatraz_restore_state",site.masked.duplicate())
	factory = jobs.Document.load_model("PTRAZ",jobs.game.game_folder,true)
	site.add_child(factory); factory.global_transform = factory_pose
	jobs.game.natural_light.attach(factory); jobs.game.water_visuals.attach(factory)
	hull = StaticBody3D.new(); factory.add_child(hull)
	for mesh in factory.find_children("*","MeshInstance3D",true,false):
		var shape := CollisionShape3D.new(); shape.shape = mesh.mesh.create_trimesh_shape()
		shape.transform = factory.global_transform.affine_inverse()*mesh.global_transform
		hull.add_child(shape)
	for index in 8:
		var gun := preload("res://aquatraz_gun.gd").new(); factory.add_child(gun)
		gun.rotation.y = deg_to_rad(22.5+index*45.0)
		# Retail gun-frame matrix translates2.5 outward; its separate broadphase
		# sphere is at1.5. Fit our damage collider to the visible gun itself.
		gun.position = gun.basis.z*2.5
		gun.setup(jobs.game,jobs.Document.load_model("TRAZGUN",jobs.game.game_folder))
		gun.destroyed.connect(_gun_destroyed); guns.append(gun)
		jobs.game.natural_light.attach(gun); jobs.game.water_visuals.attach(gun)
	for index in range(1,5): plasma.append(preload("res://clump_loader.gd")._load_texture(jobs.game.game_folder,"PLASMA%d"%index,"PLASMAM%d"%index,{}))
	for row in jobs._rows(44):
		var pose: Transform3D = jobs._pose(row)
		var index := int(row.get("param1",0))
		match int(row.ObjectID):
			1: shield_left = pose.origin
			2: shield_right = pose.origin
			3:
				var model := "TRADHERD" if index%2 == 1 else "TECHHERD"
				var ship: Node3D = jobs._boat(model,pose,1 if index%2 == 1 else 2,30,1.5)
				if ship != null: ship.combat_enabled = false; modulators.append(ship)
			4:
				var ship: Node3D = jobs._boat("TRAD-SUB" if index%2 == 1 else "TECHNEW",pose,1 if index%2 == 1 else 2,10 if index%2 == 1 else 15)
				if ship != null: ship.combat_enabled = false; allies.append(ship)
	# Startup group2 ObjectID4 is Aquatraz's three dormant ground defences.
	for row in jobs._rows(2):
		if int(row.get("ObjectID",-1)) != 4: continue
		var gun: Node3D = jobs.game.world_root.get_node_or_null("Scenery/TURRET_%d/GunTurret"%int(row.index))
		if gun == null: continue
		site.masked.append({"node":weakref(gun),"armed":gun.tuning.turret_armed,"owner":gun.mission_owner})
		gun.mission_owner = jobs.id; gun.tuning.turret_armed = true; ground_guns.append(gun)
	_build_shield()

func _build_shield() -> void:
	shield = StaticBody3D.new(); site.add_child(shield)
	var width := absf(shield_right.x-shield_left.x)+7.0
	shield.global_position = Vector3((shield_left.x+shield_right.x+7.0)*0.5,jobs.game.pilot.surface_height-6.062,shield_left.z)
	var collision := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(width,14,0.15); collision.shape = box; shield.add_child(collision)
	# Retail draws intermittent electricity rather than an opaque sheet.
	for index in 5:
		var arc := preload("res://submarine_weapons.gd").create_arc(jobs.game.pilot,jobs.game.weapons.frames)
		shield.add_child(arc); arc.set_physics_process(false); arc.camera = jobs.game.camera
		arc.settings.beam_width = 0.04; shield_arcs.append(arc)

func _shield(on: bool) -> void:
	shield.visible = on
	# Only the specially modified player can cross the lowered field. Retail
	# retains its rejection of other ships and projectiles during this window.
	if on: shield.remove_collision_exception_with(jobs.game.pilot)
	else: shield.add_collision_exception_with(jobs.game.pilot)
	if not on:
		for arc in shield_arcs: arc.firing = false; arc.beam.hide()

func _step_shield(delta: float) -> void:
	if not shield.visible: return
	shield_clock -= delta; shield_flash = maxf(0,shield_flash-delta)
	if shield_clock <= 0:
		shield_clock = randf_range(1.2,2.4); shield_flash = 0.12
		var player: Vector3 = jobs.game.pilot.global_position
		for arc in shield_arcs:
			var point := Vector3(clampf(player.x,shield_left.x,shield_right.x+7),clampf(player.y,shield.global_position.y-7,shield.global_position.y+7),shield_left.z)
			arc.beam_start = point+Vector3(randf_range(-1,1),randf_range(-1,1),0)
			arc.beam_end = arc.beam_start+Vector3(randf_range(-1,1),randf_range(-1,1),0)
	for arc in shield_arcs:
		arc.firing = shield_flash > 0; arc.beam.visible = arc.firing

func step(delta: float) -> void:
	if resolved: return
	age += delta
	_step_shield(delta)
	if destroyed:
		rotation_speed = maxf(0,rotation_speed-deg_to_rad(12.5)*delta)
		factory.rotate_y(rotation_speed*delta)
		if rotation_speed <= 0:
			_demolish(); site.committed = true; resolved = true
			jobs.radio("ar9",true); jobs._resolve(true,1,1)
		return
	if spinup: rotation_speed = minf(NORMAL_SPIN*2,rotation_speed+deg_to_rad(31.25)*delta)
	factory.rotate_y(rotation_speed*delta)
	_step_guns(delta)
	if age >= deadline:
		match jobs.phase:
			"rendezvous": jobs.radio("ar1"); jobs.phase = "approach"; deadline = age+4
			"approach":
				if not modulators.is_empty() and jobs.game.pilot.global_position.distance_to(modulators[0].global_position) < 8:
					jobs.radio("ar2"); jobs.phase = "modulating"; deadline = age+18
				else: deadline = age+2
			"modulating": jobs.radio("ar3"); jobs.phase = "modulation_warning"; deadline = age+18
			"modulation_warning": jobs.radio("ar4"); _shield(false); jobs.phase = "shield_open"; deadline = age+12
			"shield_open":
				if jobs.game.pilot.global_position.z >= shield_left.z:
					jobs.radio("ar5"); deadline = age+18
				else:
					jobs.radio("ar6"); _shield(true); jobs.phase = "attack"; reinforcement = age+2
	if reinforcement >= 0 and age >= reinforcement:
		var count := enemies.filter(func(enemy: Node3D) -> bool: return is_instance_valid(enemy) and not enemy.dead).size()
		if count < 2: _spawn_pirate()
		reinforcement = age+12
	for ally in allies:
		if not is_instance_valid(ally) or ally.dead: continue
		if not is_instance_valid(ally.combat_target) or ally.combat_target.get("dead") == true:
			for enemy in enemies:
				if is_instance_valid(enemy) and not enemy.dead:
					ally.combat_enabled = true; ally.combat_target = enemy.body; break
	bay = move_toward(bay,1.0 if jobs.phase == "attack" else 0.0,delta*2.5)
	for mesh in factory.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh.get_blend_shape_count() == 2:
			mesh.set_blend_shape_value(0,bay); mesh.set_blend_shape_value(1,0)

func _step_guns(delta: float) -> void:
	var player: Node3D = jobs.game.pilot
	var exclusions: Array[RID] = [hull.get_rid()]
	for gun in guns: exclusions.append(gun.get_rid())
	for gun in guns:
		if gun.dead: continue
		gun.cooldown = maxf(0,gun.cooldown-delta)
		var offset: Vector3 = player.global_position-gun.global_position
		if offset.length() >= 15: continue
		var local: Vector3 = gun.global_basis.inverse()*offset
		gun.barrel.rotation.x = move_toward(gun.barrel.rotation.x,-atan2(local.y,Vector2(local.x,local.z).length()),rotation_speed*delta)
		gun.collider.rotation = gun.barrel.rotation
		var forward: Vector3 = gun.barrel.global_basis.z.normalized()
		if forward.dot(offset.normalized()) < 0.949 or gun.cooldown > 0: continue
		var point: Vector3 = gun.barrel.to_global(Vector3(0,0,2.5))
		var query := PhysicsRayQueryParameters3D.create(point,player.global_position,15,exclusions)
		var hit: Dictionary = jobs.game.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider != player: continue
		var shot := preload("res://aquatraz_plasma.gd").new(); jobs.game.world_root.add_child(shot)
		shot.setup(jobs.game,plasma,point,forward,exclusions)
		gun.cooldown = 0.2

func _spawn_pirate() -> void:
	var pose := factory_pose
	pose.basis = factory.global_basis
	pose.origin += factory.global_basis*Vector3(0,0,5)
	var enemy: Node3D = jobs._boat("PIRATE",pose,3,30,2.5)
	if enemy == null: return
	jobs._place_vessel_clear(enemy,true)
	enemy.engage_player = true; enemy.pursue_offscreen = true; enemies.append(enemy)
	jobs.radio("ar7")

func _gun_destroyed(_gun: Node3D) -> void:
	var remaining := guns.filter(func(gun: Node3D) -> bool: return not gun.dead).size()
	if remaining == 3: spinup = true; jobs.radio("ar8")
	if remaining == 0:
		destroyed = true; reinforcement = -1

func target_body() -> CollisionObject3D:
	return null

func _demolish() -> void:
	jobs.burst(factory.global_position,3)
	var demolition := preload("res://base_destruction.gd").new(); jobs.game.world_root.add_child(demolition)
	demolition.setup_vessel(factory,jobs.game.submarine_traffic)
	factory.hide(); hull.collision_layer = 0; _shield(false)
	shield.collision_layer = 0
	for gun in ground_guns:
		if is_instance_valid(gun): gun.retaliation = 0; gun.tuning.turret_armed = false; gun.mission_owner = ""

func _retained_step(delta: float) -> void:
	if not factory.visible: return
	_step_shield(delta)
	if destroyed:
		rotation_speed = maxf(0,rotation_speed-deg_to_rad(12.5)*delta)
		if rotation_speed <= 0: _demolish(); return
	elif spinup: rotation_speed = minf(NORMAL_SPIN*2,rotation_speed+deg_to_rad(31.25)*delta)
	factory.rotate_y(rotation_speed*delta); _step_guns(delta)

func release_survivors() -> void:
	Survivors.release(jobs,enemies)
	for ally in allies+modulators:
		if is_instance_valid(ally) and not ally.dead: Survivors.depart(jobs,ally)
	if not site.committed:
		jobs.actors.erase(site); jobs.runtime.retain_scene_until_docking(site); retained = true
		site.stepped.connect(_retained_step)
	resolved = true

func clear() -> void:
	if retained: return # Retained defences keep working and remain destructible.
	for gun in guns:
		if is_instance_valid(gun) and gun.destroyed.is_connected(_gun_destroyed): gun.destroyed.disconnect(_gun_destroyed)
	if not retained and not site.committed:
		var city: Node3D = jobs.game.submarine_traffic.port_by_id(5).get("node")
		if city != null: city.remove_meta("mission_dock_disabled")
