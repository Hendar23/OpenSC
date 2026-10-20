extends RefCounted
## Local combat orders; travel physics and weapons remain on the vessel.
var phase := "approach"
var elapsed := 0.0
var decision_clock := 0.0
var route_clock := 0.0
var goal := Vector3.INF
var heading := Vector3.BACK
var side := Vector3.RIGHT
var target_id := 0
var target_point := Vector3.INF
var passes := 0
var turn_sign := 1.0
var lane_width := 3.0
var altitude := 0.0

func reset() -> void:
	phase = "approach"; elapsed = 0; decision_clock = 0; route_clock = 0
	goal = Vector3.INF; target_point = Vector3.INF; target_id = 0; passes = 0

func advance(agent: Node3D, victim: Node3D, delta: float) -> void:
	if target_id != victim.get_instance_id():
		reset(); target_id = victim.get_instance_id(); agent.path.clear()
		turn_sign = -1.0 if agent.random.randf() < 0.5 else 1.0
		lane_width = agent.random.randf_range(2.5,3.5); altitude = agent.random.randf_range(-0.7,0.7)
	elapsed += delta; decision_clock -= delta; route_clock -= delta
	var offset := victim.global_position-agent.global_position
	if decision_clock <= 0:
		decision_clock = 0.25+fmod(float(agent.get_instance_id()%17)*0.023,0.12)
		var speed: float = agent.tuning.npc_speed
		var lead: Vector3 = victim.velocity if victim is CharacterBody3D else victim.linear_velocity if victim is RigidBody3D else Vector3.ZERO
		var predicted: Vector3 = victim.global_position+lead*minf(0.8,offset.length()/maxf(1,speed)*0.2)
		if phase == "approach":
			heading = agent.global_position.direction_to(predicted)
			side = heading.cross(Vector3.UP).normalized()
			if side.is_zero_approx(): side = Vector3.RIGHT
			side *= turn_sign
			goal = predicted-heading*5.5
			if offset.length() < 9:
				phase = "pass"; elapsed = 0; passes += 1
				goal = predicted+heading*5.0+side*lane_width
				agent.path.clear(); route_clock = 0
		elif phase == "pass":
			if (agent.global_position-victim.global_position).dot(heading) > 2.5 or agent.global_position.distance_to(goal) < 1.8 or elapsed > 7:
				phase = "extend"; elapsed = 0
				goal = agent.global_position+heading*6+side*2
				agent.path.clear(); route_clock = 0
		elif phase == "extend":
			if agent.global_position.distance_to(goal) < 2 or elapsed > 4:
				phase = "rejoin"; elapsed = 0
				goal = predicted+side*8-heading*2+Vector3.UP*altitude
				agent.path.clear(); route_clock = 0
		elif phase == "rejoin":
			if agent.global_position.distance_to(goal) < 2.5 or elapsed > 7:
				phase = "approach"; elapsed = 0; goal = Vector3.INF
				agent.path.clear(); route_clock = 0; decision_clock = 0
		if phase == "approach" and target_point.distance_to(victim.global_position) > 3: agent.path.clear()
	if agent.path.is_empty() and route_clock <= 0 and goal.is_finite():
		route_clock = 0.75; target_point = victim.global_position
		agent.path = agent.system.route(agent.global_position,goal)
		if agent.path.is_empty():
			# Confined water may not fit a broad pass; retain a valid approach
			# around scenery without unbounded path requests or ramming it.
			agent.path = agent._attack_route(victim.global_position)
	if not agent.path.is_empty(): agent._travel_without_target(delta)
	else: agent._coast(delta)
