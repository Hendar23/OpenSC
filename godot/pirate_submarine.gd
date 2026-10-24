extends "res://trader_submarine.gd"
signal player_attack_started
## Authored enemies share vessel movement, damage, wakes and wreck effects.
## Mission activation and mission radio dialogue belong to the mission system.
const PIRATE_MODELS := ["PIRATE","PIRATE2","PIRATE3"]
const PIRATE_DEFAULTS := {"npc_speed":2.5,"npc_health":30.0,"npc_sustain":0.3,"npc_respawn":false,"npc_respawn_delay":120.0,"npc_detection":25.0,"npc_attack_range":15.0,"npc_fire_interval":1.5,"npc_faction":3}
const PIRATE_LIMITS := {"npc_speed":[0.1,8.0],"npc_health":[0.1,10000.0],"npc_sustain":[0.0,100.0],"npc_respawn_delay":[1.0,3600.0],"npc_detection":[1.0,200.0],"npc_attack_range":[1.0,100.0],"npc_fire_interval":[0.1,60.0],"npc_faction":[3,3]}
var roaming := false
var victim: Node3D
var replan := 0.0
var cooldown := 0.0
var missile_template: Node3D
var hitbox: CharacterBody3D
var bubble_trail: Node3D
var attack_run = preload("res://npc_attack_run.gd").new()
var shot_retry := 0.0
var acquire_clock := 0.0
var fallback_probe := 0
var player_attack_announced := false

static func install_pirate(model: Node3D, values: Dictionary) -> Node3D:
	var agent = preload("res://trader_submarine.gd").install(model,values,load("res://pirate_submarine.gd"))
	agent.tuning = PIRATE_DEFAULTS.duplicate()
	for key in PIRATE_DEFAULTS: agent.tuning[key] = values.get(key,PIRATE_DEFAULTS[key])
	agent.body.set_meta("faction",3)
	agent.hitbox = agent.body
	return agent

func health_multiplier() -> float:
	# Includes custom/mod pirate hulls, authored pirates and the opening mission.
	return 2.0

func reset() -> void:
	super.reset()
	victim = null; cooldown = 0; replan = 0; wait = 0; shot_retry = 0; acquire_clock = 0; fallback_probe = 0; attack_run.reset()
	player_attack_announced = false

func set_local_simulation(on: bool) -> void:
	if on != local_simulation:
		victim = null; path.clear(); cooldown = 0; replan = 0; attack_run.reset()
	super.set_local_simulation(on)

func configure_resources(folder: String) -> void:
	if is_instance_valid(missile_template): missile_template.free()
	missile_template = preload("res://clump_loader.gd").load_clump(folder.path_join("CLUMPS/MISSILE.DFF"))
	if missile_template != null:
		add_child(missile_template); missile_template.hide()
	bubble_trail = system.bubbles

func _advance_motion(delta: float) -> void:
	if dead:
		super._advance_motion(delta); return
	if _ambient_attacks_suppressed():
		if is_instance_valid(victim):
			victim = null; path.clear(); attack_run.reset()
		_roam(delta); return
	cooldown = maxf(0,cooldown - delta); replan -= delta; shot_retry = maxf(0,shot_retry-delta); acquire_clock -= delta
	if not _valid_target(victim):
		victim = null
		if acquire_clock <= 0:
			victim = _nearest_target(); acquire_clock = 0.25+fmod(float(get_instance_id()%19)*0.017,0.12)
	if victim == null:
		if roaming:
			_roam(delta); return
		path.clear(); _coast(delta); return
	var offset := victim.global_position - global_position
	var distance := offset.length()
	if distance > float(tuning.npc_detection) * 1.5:
		victim = null; path.clear(); _coast(delta); return
	attack_run.advance(self,victim,delta)
	if distance > float(tuning.npc_attack_range) or cooldown > 0 or shot_retry > 0 or missile_template == null: return
	var heading: Vector3 = get_parent().global_basis.z.normalized()
	var muzzle: Vector3 = get_parent().to_global(Vector3(0,-0.05,1))
	# A passing hull is still turning. Aim the shot from its actual muzzle,
	# rather than treating the broad forward firing cone as weapon accuracy.
	var shot_direction := muzzle.direction_to(victim.global_position)
	if heading.dot(shot_direction) <= 0.85: return
	shot_retry = 0.12
	var query := PhysicsRayQueryParameters3D.create(muzzle,victim.global_position,15,[body.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider != victim: return
	if victim == system.player and not player_attack_announced:
		player_attack_announced = true; player_attack_started.emit()
	var missile := preload("res://turret_missile.gd").new()
	system.get_parent().add_child(missile)
	missile.inflict = 8.0
	missile.setup(self,missile_template,muzzle,shot_direction,victim,false)
	missile.get_child(0).show()
	cooldown = float(tuning.npc_fire_interval) * random.randf_range(0.8,1.2)

func _continuous_route() -> bool:
	return roaming or is_instance_valid(victim) or super._continuous_route()

func _constrain_motion(delta: float, direction: Vector3) -> void:
	# Turning inertia must not carry a combat hull outside navigable water.
	# Once there, every route request rejects its own starting point.
	if not is_instance_valid(victim) or motion.velocity.is_zero_approx(): return
	if system.water_clear(global_position+motion.velocity*delta): return
	var correction := direction.normalized()*minf(motion.velocity.length(),float(tuning.npc_speed)*0.65)
	if not direction.is_zero_approx() and system.segment_clear(global_position,global_position+correction*delta):
		motion.velocity = correction
	else: motion.velocity = Vector3.ZERO

func _valid_target(target: Node3D) -> bool:
	if _ambient_attacks_suppressed(): return false
	if not is_instance_valid(target) or not target.is_visible_in_tree(): return false
	if target.get("dead") == true: return false
	if target.get("active") == false: return false
	if target.get_meta("bubble_screened",false): return false
	return true

func _ambient_attacks_suppressed() -> bool:
	if not roaming or system == null: return false
	var population: Node = system.get("roaming_population")
	return is_instance_valid(population) and self in population.ships and population.attacks_suppressed()

func prepare_abstract_route() -> bool:
	# Ambient pirates/patrols roam without acquiring victims or firing unseen.
	victim = null; destination = 0; port = {}
	if not roaming: return false
	var ids: PackedInt64Array = system.graph.get_point_ids()
	if ids.is_empty(): return false
	var point: Vector3 = system.graph.get_point_position(ids[random.randi_range(0,ids.size() - 1)])
	path = system.abstract_route(global_position,point)
	if path.is_empty(): wait = 1
	return not path.is_empty()

func _nearest_target() -> Node3D:
	var nearest: Node3D
	var best := float(tuning.npc_detection) * float(tuning.npc_detection)
	var candidates: Array = [system.player]
	for agent in system.traders:
		if agent != self and int(agent.tuning.npc_faction) != 3: candidates.append(agent.body)
	for candidate in candidates:
		if not _valid_target(candidate): continue
		var distance := global_position.distance_squared_to(candidate.global_position)
		if distance < best: nearest = candidate; best = distance
	return nearest

func take_weapon_damage(strength: float, source: Vector3 = Vector3.ZERO) -> void:
	super.take_weapon_damage(strength,source)
	# Civilian damage response flees; pirates stay and fight.
	flee = 0

func burst(point: Vector3, size: float) -> void:
	var effect := preload("res://mine_explosion.gd").new()
	system.get_parent().add_child(effect); effect.global_position = point
	effect.setup(system.explosion_frames,size,system.explosion_sound)

func _roam(delta: float) -> void:
	if path.is_empty():
		if replan > 0:
			_coast(delta); return
		replan = 1.0
		var ids: PackedInt64Array = system.graph.get_point_ids()
		for attempt in range(12):
			if ids.is_empty(): break
			var point: Vector3 = system.graph.get_point_position(ids[random.randi_range(0,ids.size()-1)])
			if point.distance_to(global_position) < 15: continue
			path = system.route(global_position,point)
			if not path.is_empty(): break
	if not path.is_empty(): super._advance_motion(delta)
	else: _coast(delta)

func take_weapon_damage_from(strength: float, source: Vector3, owner_body: Node3D) -> void:
	var alive := not dead
	apply_attributed_damage(strength,source,owner_body)
	if alive and dead and system != null and is_instance_valid(owner_body) and owner_body == system.player:
		system.pirate_defeated.emit(global_position)

func _travel_without_target(delta: float) -> void:
	super._advance_motion(delta)

func _clear_shot(from: Vector3, to: Vector3) -> bool:
	if system.space == null: return true
	return system.space.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1)).is_empty()

func _attack_route(target: Vector3) -> PackedVector3Array:
	var away := global_position - target
	if away.length_squared() < 0.001: away = Vector3.FORWARD
	var direct := target + away.normalized() * 5.5
	if _clear_shot(direct,target):
		var direct_path: PackedVector3Array = system.route(global_position,direct)
		if not direct_path.is_empty(): return direct_path
	# A dock can obstruct the straight standoff point, or stand between us and
	# a nearby target. Try clear firing positions around/above it before waiting.
	away.y = 0; away = away.normalized()
	if away.is_zero_approx(): away = Vector3.FORWARD
	# Spread failed alternative searches over successive decisions rather than
	# running every angle/height for every combatant in the same physics tick.
	var angles := [45.0,-45.0,90.0,-90.0,180.0]
	for attempt in range(3):
		var probe := fallback_probe; fallback_probe = (fallback_probe+1)%10
		var point: Vector3 = target + away.rotated(Vector3.UP,deg_to_rad(angles[probe%5])) * 5.5 + Vector3.UP * (0.0 if probe < 5 else 3.0)
		if not system.water_clear(point) or not _clear_shot(point,target): continue
		var candidate: PackedVector3Array = system.route(global_position,point)
		if not candidate.is_empty(): return candidate
	return PackedVector3Array()
