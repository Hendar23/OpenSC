extends RefCounted

const MIN_DISTANCE := 0.35
const DEFAULT_DISTANCE := 0.9
const MAX_DISTANCE := 16.0
const IDLE_TURN_FOLLOW := 0.35
const FORWARD_TURN_FOLLOW := 3.0
var orbit_yaw := 0.0
var initialized := false
var obstruction_distance := -1.0
var obstruction_hold := 0.0

func clear_distance(desired: float, allowed: float, delta: float, snap: bool = false) -> float:
	allowed = clampf(allowed,0.02,desired)
	var blocked := allowed < desired - 0.01
	var comfortable := maxf(0.02,allowed - 0.2) if blocked else desired
	if snap or obstruction_distance < 0:
		obstruction_distance = comfortable; obstruction_hold = 0.0
	else:
		if blocked: obstruction_hold = 0.18
		else: obstruction_hold = maxf(0.0,obstruction_hold - delta)
		if comfortable < obstruction_distance or obstruction_hold <= 0:
			obstruction_distance = lerpf(obstruction_distance,comfortable,1.0-exp(-(18.0 if blocked else 3.0)*delta))
		obstruction_distance = minf(obstruction_distance,allowed)
	return obstruction_distance

func resume(camera_position: Vector3, target: Vector3) -> void:
	var offset := camera_position - target
	if Vector2(offset.x, offset.z).length_squared() > 0.001:
		orbit_yaw = atan2(offset.x, offset.z)
	initialized = true

func desired_position(target: Vector3, ship_yaw: float, velocity: Vector3, forward: Vector3, forward_limit: float, distance: float, delta: float, snap: bool = false) -> Vector3:
	if snap or not initialized:
		orbit_yaw = ship_yaw
		initialized = true
	else:
		var fraction := clampf(maxf(0.0, velocity.dot(forward)) / maxf(0.01, forward_limit), 0.0, 1.0)
		var rate := lerpf(IDLE_TURN_FOLLOW, FORWARD_TURN_FOLLOW, fraction)
		orbit_yaw = lerp_angle(orbit_yaw, ship_yaw, 1.0 - exp(-rate * delta))
	return target + Vector3(sin(orbit_yaw), 0.4, cos(orbit_yaw)) * distance

func cargo_distance(distance: float, extent: float) -> float:
	# A temporary view offset; leave the player's chosen camera distance intact.
	return distance + clampf(extent * 0.55,1.25,4.0)
