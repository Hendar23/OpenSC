extends "res://fish_controller.gd"
## Scripted fish retain ordinary swimming, collision, animation and combat.
var route := PackedVector3Array()
var route_index := 0
var route_finished := false
var contact_victim: Node3D
var contact_clock := 0.0

func _choose_goal() -> void:
	if route.is_empty(): super._choose_goal(); return
	goal = route[mini(route_index,route.size()-1)]; turn_timer = 60.0

func _physics_process(delta: float) -> void:
	if not route.is_empty() and not route_finished:
		if global_position.distance_to(route[route_index]) < 0.7:
			if route_index < route.size()-1: route_index += 1
			else: route_finished = true
		goal = route[route_index]; turn_timer = 60
		# The shared fish controller applies a home-radius leash after steering.
		# Advance that home with the route so it cannot turn the specimen back.
		home = goal
	super._physics_process(delta)
	contact_clock = maxf(0,contact_clock-delta)
	# The original eel can damage the mine by striking it. Generic wildlife
	# combat selects submarines; preserve this separate scenery contact damage.
	if is_instance_valid(contact_victim) and not dead and contact_clock <= 0:
		for index in range(get_slide_collision_count()):
			if get_slide_collision(index).get_collider() == contact_victim:
				contact_clock = 1.0; contact_victim.take_weapon_damage(maxf(0.5,swim_speed),global_position); break
