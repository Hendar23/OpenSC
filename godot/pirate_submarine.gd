extends "res://trader_submarine.gd"
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

static func install_pirate(model: Node3D, values: Dictionary) -> Node3D:
	var agent = preload("res://trader_submarine.gd").install(model,values,load("res://pirate_submarine.gd"))
	agent.tuning = PIRATE_DEFAULTS.duplicate()
	for key in PIRATE_DEFAULTS: agent.tuning[key] = values.get(key,PIRATE_DEFAULTS[key])
	agent.body.set_meta("faction",3)
	# The civilian Frame_1 fallback is not a verified pirate propeller.
	if not model.get_meta("submarine_parts",{}).has("main_propeller"): agent.propeller = null
	agent.hitbox = agent.body
	return agent

func reset() -> void:
	super.reset()
	victim = null; cooldown = 0; replan = 0; wait = 0

func set_local_simulation(on: bool) -> void:
	if on != local_simulation:
		victim = null; path.clear(); cooldown = 0; replan = 0
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
	cooldown = maxf(0,cooldown - delta); replan -= delta
	if not _valid_target(victim): victim = _nearest_target()
	if victim == null:
		if roaming:
			_roam(delta); return
		path.clear(); speed = 0; body.velocity = Vector3.ZERO; return
	var offset := victim.global_position - global_position
	var distance := offset.length()
	if distance > float(tuning.npc_detection) * 1.5:
		victim = null; path.clear(); body.velocity = Vector3.ZERO; return
	# Approach diagonally through the shared water navigation, stopping at the
	# original five-to-six unit fighting distance rather than ramming a target.
	var clear_shot := _clear_shot(global_position,victim.global_position)
	if distance > 6 or not clear_shot:
		if replan <= 0:
			replan = 0.75; path = _attack_route(victim.global_position)
		if not path.is_empty(): super._advance_motion(delta)
	else:
		path.clear(); speed = 0; body.velocity = Vector3.ZERO
		var model := get_parent() as Node3D
		if distance > 0.001 and absf(offset.normalized().y) < 0.98:
			model.global_basis = model.global_basis.orthonormalized().slerp(Basis.looking_at(-offset.normalized(),Vector3.UP),1 - exp(-2 * delta)).scaled_local(home.basis.get_scale())
	if distance > float(tuning.npc_attack_range) or cooldown > 0 or missile_template == null: return
	var heading: Vector3 = get_parent().global_basis.z.normalized()
	if heading.dot(offset.normalized()) <= 0.85: return
	var muzzle: Vector3 = get_parent().to_global(Vector3(0,-0.05,1))
	var query := PhysicsRayQueryParameters3D.create(muzzle,victim.global_position,15,[body.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider != victim: return
	var missile := preload("res://turret_missile.gd").new()
	system.get_parent().add_child(missile)
	missile.inflict = 8.0
	missile.setup(self,missile_template,muzzle,heading,victim,false)
	missile.get_child(0).show()
	cooldown = float(tuning.npc_fire_interval) * random.randf_range(0.8,1.2)

func _valid_target(target: Node3D) -> bool:
	if not is_instance_valid(target) or not target.is_visible_in_tree(): return false
	if target.get("dead") == true: return false
	if target.get("active") == false: return false
	return true

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
			speed = 0; body.velocity = Vector3.ZERO; return
		replan = 1.0
		var ids: PackedInt64Array = system.graph.get_point_ids()
		for attempt in range(12):
			if ids.is_empty(): break
			var point: Vector3 = system.graph.get_point_position(ids[random.randi_range(0,ids.size()-1)])
			if point.distance_to(global_position) < 15: continue
			path = system.route(global_position,point)
			if not path.is_empty(): break
	if not path.is_empty(): super._advance_motion(delta)
	else: speed = 0; body.velocity = Vector3.ZERO

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
	for lift in [0.0,3.0]:
		for angle in [45.0,-45.0,90.0,-90.0,180.0]:
			var point: Vector3 = target + away.rotated(Vector3.UP,deg_to_rad(angle)) * 5.5 + Vector3.UP * lift
			if not system.water_clear(point) or not _clear_shot(point,target): continue
			var candidate: PackedVector3Array = system.route(global_position,point)
			if not candidate.is_empty(): return candidate
	return PackedVector3Array()
