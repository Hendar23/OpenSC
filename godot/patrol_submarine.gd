extends "res://pirate_submarine.gd"
## Faction vessels share smooth navigation, wakes, damage and debris with traders.
const PATROL_MODELS := ["TRADSHUT","PRISON","TRAD2","TECH2SUB"]
const PATROL_DEFAULTS := {"npc_speed":2.0,"npc_health":10.0,"npc_sustain":0.3,"npc_respawn":true,"npc_respawn_delay":120.0,"npc_detection":25.0,"npc_attack_range":15.0,"npc_fire_interval":1.5,"npc_armed":false}
const PATROL_LIMITS := {"npc_speed":[0.1,8.0],"npc_health":[0.1,10000.0],"npc_sustain":[0,100],"npc_respawn_delay":[1,3600],"npc_detection":[1,200],"npc_attack_range":[1,100],"npc_fire_interval":[0.1,60]}
static func install_patrol(model: Node3D, values: Dictionary) -> Node3D:
	var agent = preload("res://trader_submarine.gd").install(model,values,load("res://patrol_submarine.gd"))
	agent.tuning = PATROL_DEFAULTS.merged({"npc_faction":int(values.get("npc_faction",1))})
	for key in PATROL_DEFAULTS: agent.tuning[key] = values.get(key,PATROL_DEFAULTS[key])
	agent.body.set_meta("faction",int(agent.tuning.npc_faction))
	agent.hitbox = agent.body; agent.roaming = true
	return agent
func _valid_target(target: Node3D) -> bool:
	if not super._valid_target(target) or not bool(tuning.npc_armed): return false
	# The player has no faction affiliation. Patrols do not acquire them as an enemy.
	if target == system.player: return false
	var faction := int(target.get_meta("faction",0))
	return faction == 3
func _nearest_target() -> Node3D:
	var nearest: Node3D
	var best := pow(float(tuning.npc_detection),2)
	for agent in system.traders:
		if agent == self or not _valid_target(agent.body): continue
		var distance := global_position.distance_squared_to(agent.body.global_position)
		if distance < best: nearest = agent.body; best = distance
	return nearest
func take_weapon_damage_from(strength: float, source: Vector3, owner_body: Node3D) -> void:
	# Only pirate kills pay a bounty.
	apply_attributed_damage(strength,source,owner_body)
