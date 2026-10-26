extends StaticBody3D
## Retail fumehole/fumehole2: 00415070, volcano 00417450 / 00417b10.
const Charge = preload("res://depth_charge.gd")
const Damage = preload("res://original_damage.gd")
const Rock = preload("res://volcanic_rock.gd")
const TICK := 1.0 / 25.0
const DIRECT_RANGE := 2.8
const AIM_RADIUS_SQUARED := 10.89
const ROCK_LIMIT := 24
var jobs: Node
var health := 10.0
var dead := false
var hits := 0
var misses := 0
var progress := 0
var elapsed := 0.0
var tick_credit := 0.0
var cycle_tick := 0
var heat_warning := 0.0
var shutdown_age := -1.0
var announced := false
var seismic_report := false
var pending: Array[Dictionary] = []
var rocks: Array[Node3D] = []
var models: Dictionary = {}
var sounds: Dictionary = {}
var smoke: Node3D
var bubbles: Node3D
var audio: Array[AudioStreamPlayer3D] = []
var rng := RandomNumberGenerator.new()

func _exit_tree() -> void:
	clear()

func setup(context: Node) -> void:
	jobs = context; name = "VolcanoCore"; jobs.phase = "volcano"
	# Both city variants explicitly load placement group 14 in the executable.
	for row in jobs._rows(14):
		if int(row.ObjectID) == 1: global_transform = jobs._pose(row); break
	set_meta("mission_owner",jobs.id)
	preload("res://entity_identity.gd").assign_id(self,"mission/"+jobs.id+"/volcano")
	collision_layer = 8; collision_mask = 0
	var collider := CollisionShape3D.new(); collider.shape = SphereShape3D.new()
	collider.shape.radius = 1.0; add_child(collider)
	add_to_group("depth_charge_vents")
	# The source target is invisible; the existing world supplies the crater.
	for model in ["SMALROCK","ROCK"]: models[model] = jobs.Document.load_model(model,jobs.game.game_folder)
	for sample in ["EXPL","EXPLODE1","EXPLODE2"]:
		sounds[sample] = preload("res://submarine_weapons.gd")._sound(jobs.game.game_folder,"audio.object.volcano."+sample.to_lower(),sample)
	smoke = preload("res://smoke_emitter.gd").new(); add_child(smoke)
	smoke.configure(jobs.game.game_folder,{"emission_rate":2.0,"lifetime":7.0,"start_size":0.65,"end_size":3.5,"rise_speed":1.2,"spread":0.12,"opacity":0.95})
	bubbles = preload("res://propeller_bubbles.gd").new(); bubbles.capacity = 1024; add_child(bubbles)
	bubbles.configure(jobs.game.submarine_traffic.bubbles.material.albedo_texture); bubbles.surface_height = jobs.game.pilot.surface_height
	rng.randomize()

func accepts_charge(_point: Vector3, _velocity: Vector3, _step: float) -> bool:
	# This is an open crater, not the covert base's shaft. Retain ordinary fuse
	# and terrain collision; a charge must actually explode near the core.
	return false

func take_weapon_damage(_strength: float, _source: Vector3 = Vector3.ZERO) -> void:
	pass # Retail restores core health after every non-depth-charge weapon hit.

func depth_charge_from(_strength: float, point: Vector3, _velocity: Vector3) -> void:
	if dead or jobs.id.is_empty(): return
	var offset := point-global_position
	var distance := offset.length()
	if distance >= DIRECT_RANGE:
		if Vector2(offset.x,offset.z).length_squared() >= AIM_RADIUS_SQUARED:
			misses += 1
			if misses == 3: misses = 0; jobs.radio("n14")
		elif offset.y > 0: jobs.radio("n22")
		return
	health -= Charge.damage_at(distance)*0.2
	for sample in ["EXPL","EXPLODE1","EXPLODE2"]: _sound(sample,0.0,1.0)
	if health <= 8 and progress == 0:
		pending.append({"time":elapsed+0.12,"code":"n11"}); progress = 1
	elif health <= 5 and progress == 1:
		pending.append({"time":elapsed+0.12,"code":"n12"}); progress = 2
	misses = 0; hits += 1
	if hits <= 6: jobs.radio("n%d" % (14+hits))
	if hits >= 6: health = -1.0
	if health < 0: _shutdown()

func _shutdown() -> void:
	if dead: return
	dead = true; shutdown_age = 0.0; jobs.phase = "settling"
	set_deferred("collision_layer",0); smoke.enabled = false

func target_body() -> CollisionObject3D:
	return null if dead else self

func step(delta: float) -> void:
	if jobs.id.is_empty() or jobs.phase == "finished": return
	elapsed += delta; heat_warning = maxf(0,heat_warning-delta)
	for index in range(pending.size()-1,-1,-1):
		if elapsed+0.00001 >= pending[index].time:
			jobs.radio(pending[index].code); pending.remove_at(index)
	if dead:
		shutdown_age += delta
		if not seismic_report and shutdown_age+0.00001 >= 0.4: seismic_report = true; jobs.radio("n9")
		if shutdown_age+0.00001 >= 6.8:
			jobs.radio("n10",true); jobs._resolve(true,1.0,1)
		return
	if not announced and elapsed >= 10: announced = true; jobs.radio("n8")
	tick_credit += delta
	while tick_credit+0.000001 >= TICK:
		tick_credit -= TICK; cycle_tick = (cycle_tick+1)%501
		_heat_tick()
		# Fatal heat synchronously clears the active mission and its children.
		if jobs.id.is_empty() or jobs.volcano != self: return
		var peak := cycle_tick >= 250 and cycle_tick < 450
		smoke.tuning.emission_rate = 16.0 if peak else 8.0 if cycle_tick >= 67 else 2.0
		# Separate rising columns fill the crater instead of one narrow string.
		for stream in range(3):
			var angle := TAU*float(stream)/3.0
			var offset := Vector3(cos(angle),0,sin(angle))*0.55
			bubbles.emit_from(stream,global_position+offset,Vector3.UP,1.0,24.0 if peak else 14.0,TICK)
		if cycle_tick <= 66: continue
		var roll := rng.randi() & 255
		var erupting := cycle_tick > 249 and cycle_tick < 451
		if roll < (25 if erupting else 5): _erupt(roll < 3 and erupting,erupting)
	audio = audio.filter(func(player: Variant) -> bool: return is_instance_valid(player) and not player.is_queued_for_deletion())
	for player in audio: preload("res://explosion_audio.gd").apply(player,player.get_meta("base_gain",0.0))

static func heat_at(tick: int) -> float:
	if tick < 67: return 0.05
	if tick < 250 or tick >= 450: return 0.18
	return 0.3

func _heat_tick() -> void:
	var pilot: Node3D = jobs.game.pilot
	var distance := pilot.global_position.distance_to(global_position)
	# The original radius query includes the target's hull bounds, not just
	# whether its centre has already entered the hazard sphere.
	if distance < 3+float(pilot.COLLIDER_RADIUS) and pilot.active and not pilot.dead:
		var before: float = pilot.health
		Damage.weapon(pilot,heat_at(cycle_tick)/maxf(0.1,distance),global_position,self)
		if jobs.id.is_empty() or jobs.volcano != self: return
		if (before-pilot.health)*100 > 20 and heat_warning <= 0:
			heat_warning = 6.0; jobs.radio("n21")
	# Retail heat destroys nearby damageable wildlife and vessels outright,
	# excluding the erupted rocks and the volcano itself.
	var shape := SphereShape3D.new(); shape.radius = 3.0
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = shape
	query.transform.origin = global_position; query.collision_mask = 8; query.exclude = [get_rid()]
	for hit in get_world_3d().direct_space_state.intersect_shape(query,64):
		var body: Node3D = hit.collider
		if body == pilot or body is Rock or body is Charge or body.get("dead") == true: continue
		if body.get("stats") is Dictionary and body.stats.get("behavior","") == "rock": continue
		Damage.weapon(body,10000,global_position,self)

func _erupt(large: bool, burst: bool) -> void:
	if dead: return
	smoke._emit()
	rocks = rocks.filter(func(body: Variant) -> bool: return is_instance_valid(body) and not body.is_queued_for_deletion())
	if rocks.size() >= ROCK_LIMIT: return
	var template: Node3D = models.get("ROCK" if large else "SMALROCK")
	if template == null: return
	var definition: Dictionary = preload("res://object_definitions.gd").ROCK.duplicate(true)
	definition.merge({"id":"volcanic_rock","health":0.0,"mass":10.0,"damage_sustain":20.0,"grapple_compatible":false},true)
	var rock := Rock.new()
	rock.setup(definition,template.duplicate(),0,jobs.game.pilot.surface_height,true)
	add_child(rock); rock.top_level = true
	rock.global_position = global_position+Vector3.UP*2+Vector3(rng.randi_range(0,2),rng.randi_range(0,2),rng.randi_range(0,2))*0.1
	rock.add_collision_exception_with(self); rocks.append(rock)
	var impulse := Vector3(0,1.5,0)
	if rng.randi() & 7 == 0:
		impulse = Vector3(rng.randi_range(-128,127),rng.randi_range(-64,191),rng.randi_range(-128,127)).normalized()
		impulse = (impulse+Vector3.UP)*3.0
	rock.linear_velocity = impulse*25.0/rock.mass
	rock.angular_velocity = Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1))
	jobs.game.natural_light.attach(rock); jobs.game.water_visuals.attach(rock)
	_sound("EXPLODE2",-14.0,9000.0/11025.0)
	if burst and get_tree().get_nodes_in_group("enhanced_explosions").size() < 10:
		var effect := preload("res://mine_explosion.gd").new(); add_child(effect); effect.top_level = true
		# Clear the highest lip; descending fire must emerge over the mouth,
		# rather than appearing through the volcano's sloping sides.
		effect.global_position = global_position+Vector3.UP*2.0
		effect.spill_over = true
		effect.setup(jobs.game.object_population.explosion_frames,1.5,null)

func _sound(sample: String, gain: float, pitch: float) -> void:
	audio = audio.filter(func(player: Variant) -> bool: return is_instance_valid(player) and not player.is_queued_for_deletion())
	if sounds.get(sample) == null or audio.size() >= 12: return
	var player := AudioStreamPlayer3D.new(); add_child(player); player.stream = sounds[sample]
	player.max_distance = 60; player.pitch_scale = pitch; player.set_meta("base_gain",gain)
	preload("res://explosion_audio.gd").apply(player,gain); player.finished.connect(player.queue_free); player.play(); audio.append(player)

func clear() -> void:
	dead = true; pending.clear()
	if is_instance_valid(smoke): smoke.enabled = false; smoke.clear()
	if is_instance_valid(bubbles): bubbles.clear()
	for rock in rocks:
		if is_instance_valid(rock): rock.freeze = true; rock.queue_free()
	rocks.clear()
	for player in audio:
		if is_instance_valid(player): player.stop()
	for template in models.values():
		if is_instance_valid(template): template.free()
	models.clear()
