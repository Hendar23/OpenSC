extends "res://creature_death.gd"

const Explosion = preload("res://mine_explosion.gd")
const INITIAL_SCATTER := 1.80
var collapse_unit := 0.0
var collapse_origin := Vector3.ZERO
var collapse_offset := Vector3.ZERO

func setup_submarine(pilot: Node3D, bubble_texture: Texture2D, mounts: Array[Node3D] = []) -> void:
	setup_machine(pilot,pilot.visual,bubble_texture,mounts)
	name = "SubmarineWreck"

func setup_machine(machine: Node3D, visual: Node3D, bubble_texture: Texture2D, mounts: Array[Node3D] = [], inherited_velocity: Vector3 = Vector3.ZERO) -> void:
	# The same textured fragments and rising bubbles for all mechanical wrecks.
	setup(machine,bubble_texture,null,[],null,visual,mounts)
	name = "MachineWreck"
	chunk_fade_time = 60.0; lifetime = 61.0
	for piece in pieces:
		piece.velocity *= 0.8
		piece.velocity.y = absf(piece.velocity.y) * 1.35 + 1.5
		piece.velocity += inherited_velocity
		piece.spin *= 0.65
	if bubbles != null:
		bubbles.amount = 96; bubbles.lifetime = 2.4
		bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		bubbles.emission_sphere_radius = 0.3
		bubbles.spread = 70.0
		bubbles.initial_velocity_min = 0.3; bubbles.initial_velocity_max = 1.2
		bubbles.scale_amount_min = 0.04; bubbles.scale_amount_max = 0.16
		bubbles.restart()
		preload("res://propeller_bubbles.gd").reserve_burst(bubbles)

func follow_explosion(effect: Node3D) -> void:
	if not effect.remastered: return
	collapse_origin = to_local(effect.global_position)
	configure_bubble_collapse(effect.size)

func configure_bubble_collapse(diameter: float = Explosion.EXPLOSION_DIAMETER) -> void:
	if Explosion.classic_enabled: return
	collapse_unit = Explosion.remaster_unit(diameter)
	collapse_offset = global_basis.inverse() * Explosion.RUPTURE_OFFSET * collapse_unit
	for piece in pieces:
		piece.rest_position = piece.node.position
		piece.blast_velocity = piece.velocity
		piece.velocity *= Vector3(0.12,0.05,0.12) * Explosion.REMASTER_RATE

func _move_chunk(piece: Dictionary, delta: float) -> void:
	if collapse_unit <= 0.0 or not piece.has("rest_position"):
		super._move_chunk(piece,delta)
		return
	var time := Explosion.remaster_phase(age)
	var collapse := pow(smoothstep(Explosion.COLLAPSE_START,Explosion.COLLAPSE_END,time),1.05)
	var center := collapse_origin + collapse_offset * collapse
	var travel := (1.0 - exp(-2.7 * time)) / 2.7
	var launch_velocity: Vector3 = piece.blast_velocity
	var scattered: Vector3 = piece.rest_position + launch_velocity * Vector3(0.35,0.22,0.35) * (travel * INITIAL_SCATTER)
	var part: MeshInstance3D = piece.node
	part.rotation = piece.spin * (1.0 - exp(-time)) * 0.55
	_move_chunk_to(piece,to_global(scattered.lerp(center,collapse * 0.76)))
	if time >= Explosion.COLLAPSE_END:
		piece.erase("rest_position")
		piece.erase("blast_velocity")
