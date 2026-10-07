extends "res://creature_death.gd"

func setup_submarine(pilot: Node3D, bubble_texture: Texture2D, mounts: Array[Node3D] = []) -> void:
	setup(pilot,bubble_texture,null,[],null,pilot.visual,mounts)
	name = "SubmarineWreck"
	chunk_fade_time = 60.0; lifetime = 61.0
	for piece in pieces:
		piece.velocity *= 0.5
		piece.spin *= 0.65
	if bubbles != null:
		bubbles.amount = 96; bubbles.lifetime = 2.4
		bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		bubbles.emission_sphere_radius = 0.3
		bubbles.spread = 70.0
		bubbles.initial_velocity_min = 0.3; bubbles.initial_velocity_max = 1.2
		bubbles.scale_amount_min = 0.04; bubbles.scale_amount_max = 0.16
		bubbles.restart()
