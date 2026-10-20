extends Node3D
## Retail ATTRACT 004822a0 / 00481fe0: five-unit field, at most seven
## silverbacks, attracted toward a point 1.5 units ahead of the submarine.
const RANGE := 5.0
const LIMIT := 7
var equipment: Node3D
var enabled := false
var clock := 0.0
var audio: AudioStreamPlayer
var affected: Array[Node3D] = []

func setup(context: Node3D, folder: String) -> void:
	equipment = context
	audio = AudioStreamPlayer.new(); add_child(audio)
	audio.stream = preload("res://audio_loop.gd").prepare(preload("res://submarine_weapons.gd")._sound(folder,"audio.equipment.attract","ATTRACT"),true,30)

func set_enabled(on: bool) -> void:
	if enabled == on: return
	enabled = on; clock = 0
	if not on:
		for fish in affected:
			if is_instance_valid(fish): fish.attraction_remaining = 0
		affected.clear()
		if audio != null: audio.stop()

func _physics_process(delta: float) -> void:
	if not enabled or not equipment.pilot.active or not equipment.pilot.controls_enabled or equipment.pilot.dead:
		if audio != null: audio.stop()
		return
	if audio != null and audio.stream != null:
		audio.volume_db = -20.0 + float(equipment.pilot.submarine_audio.tuning.settings.master_volume)
		if not audio.playing: audio.play()
	clock -= delta
	if clock > 0: return
	clock = 1.0/25.0
	var pilot: Node3D = equipment.pilot
	var candidates: Array[Node3D] = []
	for fish in get_tree().get_nodes_in_group("attractable_fish"):
		if fish.dead or not fish.is_physics_processing() or fish.get_world_3d() != get_world_3d(): continue
		var distance: float = pilot.global_position.distance_to(fish.global_position)
		if distance >= 1.75 and distance <= RANGE: candidates.append(fish)
	candidates.sort_custom(func(a: Node3D,b: Node3D) -> bool: return pilot.global_position.distance_squared_to(a.global_position) < pilot.global_position.distance_squared_to(b.global_position))
	affected.clear()
	for index in mini(LIMIT,candidates.size()):
		var fish: Node3D = candidates[index]
		fish.attract_to(pilot.to_global(Vector3(0,0,-1.5)),0.12)
		affected.append(fish)

func _exit_tree() -> void:
	set_enabled(false)
