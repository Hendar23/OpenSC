extends "res://pirate_submarine.gd"
## Opening encounter patrols its five database waypoints until the player is near.
signal engagement
var patrol: Array[Vector3] = []
var waypoint := 0
var engaged := false
var encounter_age := 0.0
static func install_opening(model: Node3D, values: Dictionary) -> Node3D:
	var agent = preload("res://trader_submarine.gd").install(model,values,load("res://mission_pirate.gd"))
	agent.tuning = PIRATE_DEFAULTS.duplicate(); agent.tuning.npc_health = 9.0
	agent.hitbox = agent.body; agent.body.set_meta("faction",3)
	if not model.get_meta("submarine_parts",{}).has("main_propeller"): agent.propeller = null
	return agent
func _nearest_target() -> Node3D:
	return system.player if engaged and _valid_target(system.player) else null
func _advance_motion(delta: float) -> void:
	encounter_age += delta
	if encounter_age >= 10.0 and not engaged and is_instance_valid(system.player) and global_position.distance_to(system.player.global_position) < 5.5:
		engaged = true; engagement.emit()
	if engaged or dead: super._advance_motion(delta); return
	if patrol.is_empty(): return
	if path.is_empty():
		path = system.route(global_position,patrol[waypoint]); waypoint = (waypoint + 1) % patrol.size()
	# The shared trader integrator provides smooth steering and avoidance.
	if not path.is_empty(): _patrol_motion(delta)
func _patrol_motion(delta: float) -> void:
	# Call the civilian travel integrator, bypassing pirate acquisition.
	_travel_without_target(delta)
