extends RefCounted
## Retail bomb 00424ef0; PIXIE 004326f0, lethal sphere 00432590.
const Prop = preload("res://mission_prop.gd")
const Damage = preload("res://original_damage.gd")
var jobs: Node
var ship: RigidBody3D
var bombs: Array[Dictionary] = []
var started := false
var rescued := false
var failed := false
var nearby := false
var elapsed := 0.0
var fuse_clock := 0.0
var outcome_clock := -1.0
var radio_clock := -1.0
var radio_stage := 0
var builder: RefCounted

func start() -> void:
	jobs.phase = "search"; builder = preload("res://student_rescue.gd").new(); builder.jobs = jobs
	for row in jobs._rows(40):
		var pose: Transform3D = jobs._pose(row)
		if int(row.ObjectID) == 1:
			ship = builder.prop("FREIGHT",pose,10,0.5,100000,true)
			if ship != null:
				builder.place_clear(ship)
				ship.towing_allowed = false; ship.towing_attempted.connect(_ship_tow_attempted)
				ship.freeze = true; ship.destroyed.connect(_ship_lost); jobs.target = ship
				ship.set_meta("faction",1); jobs.game.cockpit_hud.map_data.actor_markers.append(ship)
		elif int(row.ObjectID) == 2:
			var body: RigidBody3D = builder.prop("PIXIE",pose,3.5,0.1,1.0,true)
			if body == null: continue
			builder.place_clear(body)
			body.freeze = true; body.release_on_tow = true
			var item := {"body":body,"remaining":150,"active":true,"handled":false,"attached":false,"armed":false,"smoke":null}
			bombs.append(item); body.destroyed.connect(_explode.bind(item))

func step(delta: float) -> void:
	if not is_instance_valid(ship): return
	if failed:
		outcome_clock -= delta
		if started:
			fuse_clock -= delta
			if fuse_clock <= 0:
				fuse_clock += 1.2
				for item in bombs:
					if item.active: jobs.radio("an18"); _explode(item)
		if outcome_clock <= 0: jobs._resolve(false,0,2)
		return
	if rescued:
		outcome_clock -= delta
		if outcome_clock <= 0:
			jobs.radio("an14",true); jobs._resolve(true,1.0,1)
		return
	elapsed += delta
	var distance: float = ship.global_position.distance_to(jobs.game.pilot.global_position)
	if not started and distance < 12:
		started = true; radio_clock = 0.36; fuse_clock = 0.4
	if distance < 5 and not nearby: nearby = true; jobs.radio("an1")
	if not started: return
	_update_towing()
	if radio_clock >= 0:
		radio_clock -= delta
		if radio_clock <= 0 and radio_stage < 6:
			jobs.radio(["an7","an6","an5","an4","an3","an2"][radio_stage]); radio_stage += 1
			radio_clock = 28.8 if radio_stage < 6 else -1.0
	fuse_clock -= delta
	while fuse_clock <= 0 and not failed:
		fuse_clock += 1.2
		for item in bombs:
			if not item.active: continue
			item.remaining -= 1
			if item.remaining <= 0:
				jobs.radio("an18"); _explode(item)
			elif item.remaining < 30:
				if not item.armed:
					item.armed = true; jobs.radio("an17"); _smoke(item)
				elif item.remaining == 5: jobs.radio("an19")
	if not failed and bombs.all(func(item: Dictionary) -> bool: return not item.active):
		rescued = true; outcome_clock = 8.0; jobs.phase = "rescued"; radio_clock = -1

func _update_towing() -> void:
	for item in bombs:
		if not item.active or not is_instance_valid(item.body): continue
		var attached: bool = jobs.game.equipment.magnet.target == item.body
		if attached == item.attached: continue
		item.attached = attached
		if attached:
			item.handled = true
			# Handling all three synchronises every surviving fuse to the
			# original five counter steps. A late final bomb skips the five warning.
			if bombs.all(func(other: Dictionary) -> bool: return other.handled):
				var shortest := 5
				for other in bombs:
					if other.active and other.remaining > 0: shortest = mini(shortest,other.remaining)
				for other in bombs:
					if other.active: other.remaining = mini(other.remaining,shortest)
		else: item.remaining = mini(item.remaining,30)

func _smoke(item: Dictionary) -> void:
	if not is_instance_valid(item.body): return
	var smoke := preload("res://smoke_emitter.gd").new(); item.body.add_child(smoke)
	smoke.configure(jobs.game.game_folder,{"emission_rate":4.0,"start_size":0.15,"end_size":0.5,"lifetime":2.0}); item.smoke = smoke

func _explode(item: Dictionary) -> void:
	if jobs.id.is_empty() or not item.active or not is_instance_valid(item.body): return
	item.active = false; item.body.dead = true
	var point: Vector3 = item.body.global_position
	if jobs.game.equipment.magnet.target == item.body: jobs.game.equipment.magnet.release(false)
	item.body.hide(); item.body.set_deferred("collision_layer",0)
	if is_instance_valid(item.smoke): item.smoke.enabled = false; item.smoke.clear()
	var effect := preload("res://mine_explosion.gd").new(); jobs.game.world_root.add_child(effect); effect.global_position = point
	effect.setup(jobs.game.object_population.explosion_frames,5.0,preload("res://submarine_weapons.gd")._sound(jobs.game.game_folder,"audio.object.mine.explosion","EXPLODE1"))
	# The original sphere sets eligible hull health negative inside five units;
	# the fixed freighter and other PIXIES have separate, tighter chain rules.
	var sphere := SphereShape3D.new(); sphere.radius = 5.0
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = sphere; query.transform.origin = point; query.collision_mask = 15
	var excluded: Array[RID] = []
	if is_instance_valid(ship): excluded.append(ship.get_rid())
	for other in bombs:
		if is_instance_valid(other.body): excluded.append(other.body.get_rid())
	query.exclude = excluded
	var hit_bodies := {}
	for hit in jobs.game.get_world_3d().direct_space_state.intersect_shape(query,512):
		var body: Node3D = hit.collider
		if hit_bodies.has(body.get_instance_id()): continue
		hit_bodies[body.get_instance_id()] = true; Damage.weapon(body,1000000,point)
	var player: RigidBody3D = jobs.game.pilot
	if not player.dead:
		player.apply_central_impulse(point.direction_to(player.global_position)*player.mass*0.75)
	if not failed and is_instance_valid(ship) and not ship.dead and point.distance_squared_to(ship.global_position) < 2.5: ship.take_weapon_damage(1000000)
	for other in bombs:
		if other.active and is_instance_valid(other.body) and point.distance_squared_to(other.body.global_position) < 2.5: other.remaining = 1

func _ship_lost() -> void:
	if failed or jobs.id.is_empty(): return
	failed = true; jobs.phase = "lost"
	outcome_clock = 4.0
	for item in bombs:
		if item.active: item.remaining = 1
	var effect := preload("res://submarine_death.gd").new(); jobs.game.world_root.add_child(effect); effect.global_position = ship.global_position
	effect.setup_machine(ship,ship.get_child(0),jobs.game.submarine_traffic.bubble_texture)
	ship.hide(); jobs.radio("an10",true)

func delivery(body: Node3D, _city: int) -> bool:
	for item in bombs:
		if item.active and body == item.body: jobs.radio("an16"); jobs.game.equipment.magnet.decline_delivery(); return true
	return false

func _ship_tow_attempted() -> void:
	jobs.radio("an12" if rescued else "an11")

func target_body() -> CollisionObject3D:
	return ship if is_instance_valid(ship) and not ship.dead and not rescued else null

func clear() -> void:
	if is_instance_valid(ship) and ship.destroyed.is_connected(_ship_lost): ship.destroyed.disconnect(_ship_lost)
	if is_instance_valid(ship) and ship.towing_attempted.is_connected(_ship_tow_attempted): ship.towing_attempted.disconnect(_ship_tow_attempted)
	for item in bombs:
		if is_instance_valid(item.body):
			var callback := _explode.bind(item)
			if item.body.destroyed.is_connected(callback): item.body.destroyed.disconnect(callback)
	builder = null
