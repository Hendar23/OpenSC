extends "res://mission_creature.gd"
## BLOWFISH is mechanical; use the same metal wreck and explosion as ships.
var traffic: Node
var obstacle_query: PhysicsRayQueryParameters3D

func _steer(desired: Vector3, delta: float, rate: float = -1.0) -> void:
	# Retail433160 calls47e8f0 with a two-unit obstacle probe before
	# applying steering. Ordinary fish only avoid after physically colliding.
	if is_inside_tree() and not desired.is_zero_approx():
		if obstacle_query == null: obstacle_query = PhysicsRayQueryParameters3D.new()
		obstacle_query.from = global_position; obstacle_query.to = global_position+desired.normalized()*2.0
		obstacle_query.collision_mask = 1; obstacle_query.hit_back_faces = true
		obstacle_query.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(obstacle_query)
		if not hit.is_empty() and desired.dot(hit.normal) < 0:
			desired = desired.bounce(hit.normal)
	super._steer(desired,delta,rate)

func _death_effect() -> void:
	var holder: Node = population.world if population != null else get_parent()
	var wreck := preload("res://submarine_death.gd").new()
	holder.add_child(wreck); wreck.global_position = global_position
	wreck.setup_machine(self,get_child(1),traffic.bubble_texture,[],velocity)
	var explosion := preload("res://mine_explosion.gd").new()
	holder.add_child(explosion); explosion.global_position = global_position
	explosion.setup(traffic.explosion_frames,1.0,traffic.explosion_sound)
