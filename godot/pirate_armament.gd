extends Node3D
## Optional zapper loadouts for standard torpedo-armed submarines.
const Assets = preload("res://clump_loader.gd")
const Zapper = preload("res://submarine_weapons.gd")
const Damage = preload("res://original_damage.gd")
const BURST_DURATION := 0.4
# A regular burst deals half the raw damage of a full-speed pirate torpedo hit on a stationary target.
const BURST_DAMAGE := 1.875
const DAMAGE_PER_TICK := BURST_DAMAGE / (BURST_DURATION * Damage.TICKS_PER_SECOND)
const WEAPONS := ["missile","zapper","zapperup"]
var agent: Node3D
var weapon_id := "missile"
var folder: String
var pilot: Node3D
var arcs: Array[Node3D] = []
var zap_audio: AudioStreamPlayer3D
var burst_remaining := 0.0
var damage_clock := 0.0
var burst_in_frame := false
var frame_ticks := 0

static func weapon_for_roll(roll: int) -> String:
	if roll < 50: return "missile"
	if roll < 80: return "zapper"
	return "zapperup"

func setup(owner_agent: Node3D, asset_folder: String) -> void:
	agent = owner_agent; pilot = agent.body; folder = asset_folder
	set_process(false)

func _prepare_effects() -> void:
	if zap_audio != null: return
	var frames: Array[Texture2D] = []
	for index in range(1,4): frames.append(Assets._load_texture(folder,"ZAPPER%d" % index,"ZAPPER%dM" % index,{}))
	for index in range(2):
		var arc := Zapper.create_arc(pilot,frames); add_child(arc); arc.set_physics_process(false); arcs.append(arc)
	zap_audio = AudioStreamPlayer3D.new()
	zap_audio.stream = preload("res://audio_loop.gd").prepare(Zapper._sound(folder,"audio.weapon.zapper","ELECTRIC"),true,35)
	zap_audio.unit_size = 2.0; zap_audio.max_distance = 25.0; zap_audio.max_db = 0.0
	add_child(zap_audio)
	set_process(true)

func select_weapon(id: String) -> void:
	reset(); weapon_id = id if id in WEAPONS else "missile"
	agent.cooldown = 0.0

func weapon_range() -> float:
	return minf(float(agent.tuning.npc_attack_range),5.0 if weapon_id == "zapperup" else 2.5) if weapon_id in ["zapper","zapperup"] else float(agent.tuning.npc_attack_range)

func reset() -> void:
	burst_remaining = 0.0; damage_clock = 0.0; burst_in_frame = false; frame_ticks = 0
	for arc in arcs: arc.firing = false; arc.beam.hide()
	if zap_audio != null: zap_audio.stop()

func begin_frame(delta: float) -> void:
	burst_in_frame = burst_remaining > 0.0
	frame_ticks = _advance_burst(delta) if burst_in_frame else 0
	for arc in arcs: arc.firing = false; arc.beam.hide()

func _advance_burst(delta: float) -> int:
	var elapsed := minf(delta,burst_remaining)
	burst_remaining -= elapsed
	if burst_remaining < 0.000001: burst_remaining = 0.0
	damage_clock += elapsed * Damage.TICKS_PER_SECOND
	var ticks := int(floor(damage_clock+0.000001))
	damage_clock = maxf(0.0,damage_clock-ticks)
	return ticks

func attack(delta: float, victim: Node3D) -> void:
	if weapon_id == "missile" or (agent.cooldown > 0.0 and not burst_in_frame): return
	var muzzle: Vector3 = agent.get_parent().to_global(Vector3(0,-0.05,1))
	var aim := muzzle.direction_to(victim.global_position)
	if agent.global_position.distance_to(victim.global_position) > weapon_range() or agent.get_parent().global_basis.z.normalized().dot(aim) <= 0.85: return
	var query := PhysicsRayQueryParameters3D.create(muzzle,victim.global_position,15,[pilot.get_rid()]); query.hit_back_faces = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider != victim: return
	if victim == agent.system.player and not agent.player_attack_announced:
		agent.player_attack_announced = true; agent.player_attack_started.emit()
	if not burst_in_frame:
		burst_remaining = BURST_DURATION; damage_clock = 0.0
		frame_ticks = _advance_burst(delta)
		agent.cooldown = float(agent.tuning.npc_fire_interval) * agent.random.randf_range(0.8,1.2)
	_prepare_effects()
	var camera := get_viewport().get_camera_3d()
	if not hit.is_empty():
		Zapper.HullSurge.strike(hit.collider)
		Damage.weapon(hit.collider,DAMAGE_PER_TICK * (2.0 if weapon_id == "zapperup" else 1.0) * frame_ticks,muzzle,pilot,"zapper",hit)
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
