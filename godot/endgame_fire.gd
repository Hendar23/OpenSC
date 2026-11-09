extends Node3D
## FIREPLUME/FIREWALL00488b00/004886e0; visuals remain independent of AI.
signal caught
var game: Node
var age := 0.0
var clock := 0.0
var speed := 0.0
var chasing := false
var finished := false
var head := Vector3.ZERO

func setup(context: Node, point: Vector3) -> void:
	game = context; global_position = point; head = point

func _physics_process(delta: float) -> void:
	if finished: return
	age += delta; clock += delta
	if age >= 4:
		chasing = true; speed = minf(4.0,speed+1.25*delta)
		var offset: Vector3 = game.pilot.global_position-head
		head += offset.normalized()*minf(offset.length(),speed*delta)
		if head.distance_to(game.pilot.global_position) < 0.5:
			finished = true; caught.emit(); return
	while clock >= 0.12:
		clock -= 0.12
		var point := head if chasing else global_position+Vector3.UP*fmod(age*6.944,4.167)
		var effect := preload("res://mine_explosion.gd").new(); game.world_root.add_child(effect)
		effect.global_position = point+Vector3(randf_range(-0.25,0.25),randf_range(-0.25,0.25),0)
		effect.setup(game.submarine_traffic.explosion_frames,4.0 if chasing else 2+fmod(age*6.944,4.167)*0.2,game.submarine_traffic.explosion_sound)
