extends "res://salvage_body.gd"
var clam: Node3D
func pickup_item() -> String:
	if dead or has_meta("delivery_city"): return ""
	if is_instance_valid(clam) and not clam.fully_open(): return ""
	return str(stats.get("pickup_commodity","pearls"))

# The original holds the pearl inside its clam until suction pulls it clear.
func pull_towards(intake: Vector3, speed: float, delta: float) -> bool:
	if not is_instance_valid(clam): return false
	if not clam.fully_open(): return true
	global_position = global_position.move_toward(intake,speed * delta)
	if global_position.distance_to(clam.global_position) >= float(clam.stats.release_distance): clam.release_pearl()
	return true

func collected() -> void:
	if is_instance_valid(clam): clam.release_pearl()
