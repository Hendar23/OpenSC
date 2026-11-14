extends Node3D
## Alternative weapons belong only to the two random encounter slots.
const Assets = preload("res://clump_loader.gd")
const Zapper = preload("res://submarine_weapons.gd")
const Damage = preload("res://original_damage.gd")
var agent: Node3D
var weapon_id := "missile"
# Projectile context matches the existing Electro Bolt's player arsenal API.
var weapons: Node3D
var pilot: Node3D
var camera: Camera3D
var frames: Array[Texture2D] = []
var bolt_frames: Array[Texture2D] = []
var arcs: Array[Node3D] = []
var shots: Array[Node3D] = []
var zap_audio: AudioStreamPlayer3D
var bolt_audio: AudioStreamPlayer3D
var burst_remaining := 0.0
var damage_clock := 0.0

func setup(owner_agent: Node3D, folder: String) -> void:
	agent = owner_agent; weapons = self; pilot = agent.body
	for index in range(1,4): frames.append(Assets._load_texture(folder,"ZAPPER%d" % index,"ZAPPER%dM" % index,{}))
	for index in range(1,5): bolt_frames.append(Assets._load_texture(folder,"BOLT%d" % index,"BOLT%dM" % index,{}))
	for index in range(2):
		var arc := Zapper.create_arc(pilot,frames); add_child(arc); arc.set_physics_process(false); arcs.append(arc)
	zap_audio = _audio(preload("res://audio_loop.gd").prepare(Zapper._sound(folder,"audio.weapon.zapper","ELECTRIC"),true,35))
	bolt_audio = _audio(Zapper._sound(folder,"audio.weapon.electro.fire","ELECTRO"))

func _audio(stream: AudioStream) -> AudioStreamPlayer3D:
	var audio := AudioStreamPlayer3D.new(); audio.stream = stream
	audio.unit_size = 2.0; audio.max_distance = 25.0; audio.max_db = 0.0
	add_child(audio); return audio

func select_weapon(id: String) -> void:
	reset(); weapon_id = id if id in ["missile","zapper","zapperup","electro"] else "missile"
	agent.cooldown = 0.0

func weapon_range() -> float:
	return minf(float(agent.tuning.npc_attack_range),5.0 if weapon_id == "zapperup" else 2.5) if weapon_id in ["zapper","zapperup"] else float(agent.tuning.npc_attack_range)

func reset() -> void:
	burst_remaining = 0.0; damage_clock = 0.0
	for arc in arcs: arc.firing = false; arc.beam.hide()
	if zap_audio != null: zap_audio.stop()
	if bolt_audio != null: bolt_audio.stop()

func begin_frame(delta: float) -> void:
	burst_remaining = maxf(0.0,burst_remaining-delta)
	for arc in arcs: arc.firing = false; arc.beam.hide()

func attack(delta: float, victim: Node3D) -> void:
	if agent.cooldown > 0.0 and burst_remaining <= 0.0: return
	var muzzle: Vector3 = agent.get_parent().to_global(Vector3(0,-0.05,1))
	var aim := muzzle.direction_to(victim.global_position)
	if agent.global_position.distance_to(victim.global_position) > weapon_range() or agent.get_parent().global_basis.z.normalized().dot(aim) <= 0.85: return
	var query := PhysicsRayQueryParameters3D.create(muzzle,victim.global_position,15,[pilot.get_rid()]); query.hit_back_faces = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider != victim: return
	if victim == agent.system.player and not agent.player_attack_announced:
		agent.player_attack_announced = true; agent.player_attack_started.emit()
	camera = get_viewport().get_camera_3d()
	if weapon_id == "electro":
		var bolt := preload("res://player_projectile.gd").new()
		agent.system.get_parent().add_child(bolt); bolt.setup(self,"electro",muzzle,aim,victim)
		shots.append(bolt)
		bolt_audio.global_position = muzzle
		preload("res://explosion_audio.gd").apply(bolt_audio,0.0,"wildlife_zapper_volume")
		bolt_audio.play()
		agent.cooldown = maxf(1.5,float(agent.tuning.npc_fire_interval))
		return
	if burst_remaining <= 0.0:
		burst_remaining = 0.4; damage_clock = 0.0
		agent.cooldown = float(agent.tuning.npc_fire_interval) * agent.random.randf_range(0.8,1.2)
	damage_clock += delta * Damage.TICKS_PER_SECOND
	var ticks := int(floor(damage_clock+0.000001)); damage_clock -= ticks
	if not hit.is_empty(): Damage.weapon(hit.collider,float(Zapper.DEFAULTS.damage_per_tick) * (2.0 if weapon_id == "zapperup" else 1.0) * ticks,muzzle,pilot,"zapper",hit)
	for index in range(2 if weapon_id == "zapperup" else 1):
		var arc: Node3D = arcs[index]; arc.camera = camera
		arc.firing = camera != null; arc.beam.visible = arc.firing
		arc.beam_start = muzzle + agent.get_parent().global_basis.x * ((-0.12 if index == 0 else 0.12) if weapon_id == "zapperup" else 0.0)
		arc.beam_end = hit.get("position",victim.global_position)
	zap_audio.global_position = muzzle
	preload("res://explosion_audio.gd").apply(zap_audio,0.0,"wildlife_zapper_volume")
	if not zap_audio.playing: zap_audio.play()

func _process(_delta: float) -> void:
	if is_instance_valid(agent) and (agent.dead or not agent.local_simulation or not agent.get_parent().is_visible_in_tree()): reset()
	if zap_audio != null and not arcs.any(func(arc: Node3D) -> bool: return arc.firing): zap_audio.stop()
	for shot in shots.duplicate():
		if not is_instance_valid(shot): shots.erase(shot)
	# Free-flying bolts can outlive their launching pirate or its firing burst.
	if is_instance_valid(agent) and agent.system != null: camera = get_viewport().get_camera_3d()

func bubbles() -> Node3D:
	return agent.system.bubbles if is_instance_valid(agent) and agent.system != null else null

func burst(point: Vector3, size: float) -> void:
	if is_instance_valid(agent): agent.burst(point,size)
