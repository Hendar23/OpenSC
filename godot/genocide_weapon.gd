extends RefCounted
## Retail Project 13 mission: SC.EXE 004117b0; all four city offers share it.
const Body = preload("res://mission_walker_body.gd")
const Survivor = preload("res://mission_survivors.gd")
const DELAYS := [28.0,32.0,28.0,12.0,6.0,6.0,54.0,77.0,54.0,12.0]
const HEAD_TOW_MASS := Body.TOW_MASS
const HEAD_FREE_MASS := Body.FREE_MASS
var jobs: Node
var walker: RigidBody3D
var head: RigidBody3D
var enemies: Array[Node3D] = []
var helpers: Array[Node3D] = []
var phase := "walker"
var warning := 0
var clock := 12.0
var torpedo_hits := 0
var zapper_hits := 0.0
var guards_alert := false
var approached := false
var hit_warning := false
var low_shields := false
var chase := false
var chase_announced := false
var pursuer: Node3D
var backup_clock := -1.0
var delivery_clock := 0.0
var head_origin := Transform3D.IDENTITY
var head_meshes: Array[MeshInstance3D] = []
var armament: Node3D

func start() -> void:
	jobs.phase = "walker"
	preload("res://campaign_resources.gd").spawn_genocide_bonus(jobs.game)
	for row in jobs._rows(5):
		if int(row.get("ObjectID",0)) != 1: continue
		walker = _cargo("WALKER",jobs._pose(row),false)
		if walker == null: return
		walker.name = "Project13Walker"; walker.freeze = true
		walker.set_meta("metal_tow_target",false)
		walker.weapon_hit.connect(_walker_hit)
		# The detached WALKHEAD contains WALKER's first two atomics. Align the
		# new head to that original frame, not to the ground-level leg pivot.
		for mesh: MeshInstance3D in walker.appearance.find_children("*","MeshInstance3D",true,false):
			if mesh.name in ["Mesh_0","Mesh_1"]: head_meshes.append(mesh)
			if mesh.name == "Mesh_1": head_origin = mesh.get_parent().global_transform
		armament = preload("res://walker_armament.gd").new(); walker.add_child(armament)
		armament.setup(walker,jobs.game)
		for offset: Vector3 in [Vector3(-2,3,-1),Vector3(0,3,3),Vector3(2,3,-1)]:
			var guard: Node3D = jobs._boat("TECH2SUB",Transform3D(Basis.IDENTITY,walker.global_position+offset),2,15,3.5)
			if guard == null: continue
			guard.motion.turn_rate = deg_to_rad(105.0)
			guard.pursue_offscreen = true
			guard.player_attacked.connect(_alert_guards)
			enemies.append(guard); jobs._place_vessel_clear(guard,true)
		_mark(walker)
		break

func _cargo(model_id: String, pose: Transform3D, detached: bool) -> RigidBody3D:
	var visual: Node3D = jobs.Document.load_model(model_id,jobs.game.game_folder)
	if visual == null: return null
	if detached and is_instance_valid(armament) and is_instance_valid(armament.pitch):
		# WALKHEAD's root is WALKER's yaw frame; its child preserves the guns'
		# independent pitch. Do not tilt the entire released head with a barrel.
		var guns: Node3D = visual.find_child("Frame_1",true,false)
		if guns != null: guns.transform = armament.pitch.transform
	var body := Body.new(); body.freeze = not detached; jobs.game.world_root.add_child(body)
	body.global_transform = pose; body.add_child(visual); body.appearance = visual
	body.detached = detached; body.max_contacts_reported = 8 if detached else 0; body.health = 1.0 if detached else 20.0; body.damage_sustain = 0.1
	body.surface_height = jobs.game.pilot.surface_height; body.mass = HEAD_FREE_MASS if detached else 1.0
	body.stats = {"delivery_commodity":"Walker head","delivery_quantity":1}
	body.set_meta("damage_sustain",0.1); body.set_meta("mission_owner",jobs.id)
	preload("res://entity_identity.gd").assign_id(body,"mission/"+jobs.id+"/"+model_id.to_lower())
	var box := preload("res://submarine_equipment.gd")._bounds(preload("res://submarine_equipment.gd")._meshes(visual,Transform3D.IDENTITY))
	if detached:
		var shape := CollisionShape3D.new(); shape.shape = BoxShape3D.new(); shape.shape.size = box.size; shape.position = box.get_center(); body.add_child(shape)
	else:
		# Frozen chassis: ray/torpedo collision must follow the actual head and
		# legs, including empty gaps, rather than one enclosing box.
		for mesh: MeshInstance3D in visual.find_children("*","MeshInstance3D",true,false):
			var shape := CollisionShape3D.new(); shape.shape = mesh.mesh.create_trimesh_shape()
			shape.shape.backface_collision = true
			shape.transform = body.global_transform.affine_inverse()*mesh.global_transform
			shape.set_meta("walker_head",mesh.name in ["Mesh_0","Mesh_1"])
			shape.set_meta("walker_visual",weakref(mesh)); body.add_child(shape)
	body.set_meta("mission_target_center",box.get_center()); jobs.actors.append(body)
	jobs.game.natural_light.attach(visual); jobs.game.water_visuals.attach(visual)
	return body

func _mark(body: Node3D) -> void:
	jobs.target = body
	body.set_meta("mission_marker",true)
	body.set_meta("faction",0)
	if body not in jobs.game.cockpit_hud.map_data.actor_markers: jobs.game.cockpit_hud.map_data.actor_markers.append(body)

func target_body() -> CollisionObject3D:
	if phase == "walker" and is_instance_valid(walker): return walker
	if phase == "head" and is_instance_valid(head) and not head.dead: return head
	return null

func _alert_guards() -> void:
	if phase in ["handoff","finished"]: return
	if not guards_alert: guards_alert = true; jobs.radio("e13")
	for guard in enemies:
		if is_instance_valid(guard) and not guard.dead: _engage(guard)

func _engage(guard: Node3D) -> void:
	if guard.engage_player: return
	guard.engage_player = true; guard.acquire_clock = 0; guard.cooldown = 0
	guard.replan = 0; guard.path.clear(); guard.attack_run.reset()

func _walker_hit(strength: float, _source: Vector3, _attacker: Node3D, kind: String, head_hit: bool) -> void:
	if phase != "walker": return
	_alert_guards()
	if not head_hit:
		walker.health -= strength*walker.damage_sustain
		if walker.health > 0: return
		phase = "detaching"
		jobs.call_deferred("_detach_walker_head")
		return
	# These counters are head destruction, NOT leg-destruction progress.
	# Retail 00463410 starts the chassis at raw20 shields / .1 sustain;
	# 004117b0's three missiles / 27 gun contacts destroy the head catastrophically.
	if kind in ["missile","homers"]:
		torpedo_hits += 1
		zapper_hits = maxf(zapper_hits,float(torpedo_hits)*9.0)
		if torpedo_hits < 3: jobs.radio("e18" if torpedo_hits == 2 else "e17")
	elif kind == "zapper":
		var before := int(zapper_hits/9.0)
		zapper_hits += strength/2.5
		if int(zapper_hits/9.0) > before and zapper_hits < 27: jobs.radio("e19" if zapper_hits >= 18 else "e17")
		torpedo_hits = maxi(torpedo_hits,int(zapper_hits/9.0))
	if torpedo_hits >= 3 or zapper_hits >= 27:
		phase = "doomed"
		_catastrophe.call_deferred()

func detach_head() -> void:
	if phase != "detaching" or jobs.id.is_empty(): return
	if is_instance_valid(armament): armament.set_physics_process(false)
	for mesh in head_meshes:
		if mesh.name == "Mesh_1": head_origin = mesh.get_parent().global_transform
	head = _cargo("WALKHEAD",head_origin,true)
	if head == null: return
	head.linear_velocity = Vector3.UP*0.3
	head.destroyed.connect(_catastrophe)
	head.weapon_hit.connect(_head_hit)
	for mesh in head_meshes:
		if is_instance_valid(mesh): mesh.hide(); mesh.set_meta("exclude_from_debris",true)
	var wreck := preload("res://submarine_death.gd").new(); jobs.game.world_root.add_child(wreck)
	wreck.global_position = walker.global_position
	wreck.setup_machine(walker,walker.appearance,jobs.game.submarine_traffic.bubble_texture)
	jobs.burst(walker.global_position,1.2)
	walker.hide(); walker.collision_layer = 0
	jobs.game.cockpit_hud.map_data.actor_markers.erase(walker)
	phase = "head"; jobs.phase = "head"; warning = 6
	_mark(head)

func _head_hit(_strength: float, _source: Vector3, _attacker: Node3D, _kind: String, _head_hit: bool) -> void:
	if not hit_warning: hit_warning = true; jobs.radio("e17")

func step(delta: float) -> void:
	if phase == "finished": return
	if phase == "handoff":
		delivery_clock -= delta
		if delivery_clock <= 0: phase = "finished"; jobs._resolve(true,1.0,0)
		return
	clock -= delta
	while clock <= 0 and phase in ["walker","head"]:
		if warning in [5,9]: _catastrophe(); return
		jobs.radio("e%d" % (warning+1))
		clock += DELAYS[warning]; warning += 1
	if phase == "walker" and not approached and is_instance_valid(walker) and walker.global_position.distance_to(jobs.game.pilot.global_position) < 13.0:
		approached = true; jobs.radio("e20")
		for guard in enemies:
			if is_instance_valid(guard) and not guard.dead: _engage(guard); break
	if phase != "head" or not is_instance_valid(head): return
	var towing: bool = jobs.game.equipment.magnet.target == head
	# Original uses raw75 -> .75 ->75. OpenSC's raw1 submarine is100kg:
	# apply the physics conversion, then the owner's approved half-weight tuning.
	head.mass = HEAD_TOW_MASS if towing else HEAD_FREE_MASS
	head.raw_impact_mass = 0.75 if towing else 75.0
	if not low_shields and head.health < 0.7: low_shields = true; jobs.radio("e16")
	if towing and not jobs.tapped: jobs.tapped = true; jobs.radio("e12")
	if towing and not chase and jobs.game.pilot.global_position.distance_squared_to(jobs._city(2)) < 400.0:
		chase = true; _pursuer()
	if backup_clock >= 0:
		backup_clock -= delta
		if backup_clock <= 0:
			if not chase_announced:
				chase_announced = true; jobs.radio("e14"); backup_clock += 8.0
			else: backup_clock = -1; _backup()

func _launch(model_id: String, city: int, faction: int, shields: float) -> Node3D:
	var port: Dictionary = jobs.game.submarine_traffic.port_by_id(city)
	var agent: Node3D = jobs._boat(model_id,Transform3D(Basis.IDENTITY,port.inside),faction,shields,2.0)
	if agent == null: return null
	# Use the shared hatch/departure sequence, including player clearance and
	# sound, instead of materialising a reinforcement over an occupied dock.
	agent.port = port; agent.destination = city; agent.last_city = city
	agent.stage = "berth"; agent.wait = 0; agent.body.collision_layer = 0
	agent.get_parent().global_position = port.inside+Vector3.UP*maxf(0,-agent.bounds.position.y-0.25)
	agent.get_parent().hide()
	return agent

func _pursuer() -> void:
	# Original object 0x16 is TECHATTACKSUB1 / TECHNEW, not TECHSHUT.
	pursuer = _launch("TECHNEW",2,2,15)
	if pursuer != null:
		pursuer.engage_player = true; pursuer.pursue_offscreen = true; enemies.append(pursuer)
	backup_clock = 2.4

func _backup() -> void:
	jobs.radio("e15")
	var helper := _launch("TRAD-SUB",1,1,10)
	if helper == null: return
	helpers.append(helper)
	if is_instance_valid(pursuer) and not pursuer.dead:
		helper.combat_target = pursuer.body; helper.pursue_offscreen = true

func delivery(body: Node3D, city: int) -> bool:
	if body != head or phase != "head": return false
	if city not in [1,3]:
		jobs.game.equipment.magnet.decline_delivery(); return true
	phase = "handoff"; jobs.phase = "handoff"; delivery_clock = 6.0
	head.delivered = true; head.set_meta("delivery_city",city); head.set_meta("metal_tow_target",false)
	jobs.game.equipment.magnet.set_enabled(false)
	var guard := _launch("TRAD-SUB",city,1,10)
	if guard != null:
		guard.combat_enabled = false; guard.waypoints = PackedVector3Array([head.global_position+Vector3.UP*3]); helpers.append(guard)
	head.freeze = true; head.linear_velocity = Vector3.ZERO; head.angular_velocity = Vector3.ZERO
	jobs.runtime.active()["resolved_city"] = city
	jobs.game.cockpit_hud.map_data.actor_markers.erase(head)
	jobs.radio("e11",true)
	return true

func _catastrophe() -> void:
	if phase in ["finished","handoff"] or jobs.id.is_empty(): return
	phase = "finished"
	var body: Node3D = head if is_instance_valid(head) else walker
	if is_instance_valid(body):
		var blast := preload("res://base_destruction.gd").new(); jobs.game.world_root.add_child(blast)
		blast.setup_vessel(body,jobs.game.submarine_traffic)
	# Retail sets the global catastrophe/player-death flags, wherever the
	# player is. This is not a normal local cargo explosion that can be outrun.
	jobs.game.pilot.take_damage(100000.0)
	jobs._resolve(false,0.0,0)
	jobs.game.events.fmv_requested.emit("walker_catastrophe",0)

func release_survivors() -> void:
	_disconnect()
	Survivor.release(jobs,enemies)
	for helper in helpers: Survivor.depart(jobs,helper)

func _disconnect() -> void:
	for guard in enemies:
		if is_instance_valid(guard) and guard.player_attacked.is_connected(_alert_guards): guard.player_attacked.disconnect(_alert_guards)
	if is_instance_valid(walker) and walker.weapon_hit.is_connected(_walker_hit): walker.weapon_hit.disconnect(_walker_hit)
	if is_instance_valid(head):
		if head.destroyed.is_connected(_catastrophe): head.destroyed.disconnect(_catastrophe)
		if head.weapon_hit.is_connected(_head_hit): head.weapon_hit.disconnect(_head_hit)

func clear() -> void:
	_disconnect()
	phase = "finished"
