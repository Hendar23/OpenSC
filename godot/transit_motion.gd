extends RefCounted

# Rest-to-rest triangular/trapezoidal motion. Velocity is continuous, including
# stage boundaries; distance, speed and acceleration remain analytically bounded.
static func plan(distance: float, speed: float, acceleration: float) -> Dictionary:
	distance = absf(distance)
	if distance < 0.00001: return {"duration": 0.0, "distance": 0.0, "ramp": 0.0, "cruise": 0.0, "speed": 0.0, "acceleration": 0.0}
	if speed <= 0.0 or acceleration <= 0.0: return {"duration": INF}
	var ramp := minf(sqrt(distance / acceleration), speed / acceleration)
	var peak := acceleration * ramp
	var cruise := maxf(0.0, distance / peak - ramp)
	return {"duration": ramp * 2.0 + cruise, "distance": distance,
		"ramp": ramp, "cruise": cruise, "speed": peak, "acceleration": acceleration}

static func sample(profile: Dictionary, time: float) -> Vector2:
	if float(profile.duration) == 0.0: return Vector2.ZERO
	var t := clampf(time, 0.0, float(profile.duration))
	var ramp: float = profile.ramp
	var cruise: float = profile.cruise
	var speed: float = profile.speed
	var acceleration: float = profile.acceleration
	if t < ramp: return Vector2(acceleration * t * t * 0.5, acceleration * t)
	if t < ramp + cruise: return Vector2(speed * ramp * 0.5 + speed * (t - ramp), speed)
	var remaining := float(profile.duration) - t
	return Vector2(float(profile.distance) - acceleration * remaining * remaining * 0.5, acceleration * remaining)
