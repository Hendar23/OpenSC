extends Node3D
signal item_collected(item: String)

const CAPACITY := 5
var pilot: Node3D
var population: Node3D
var enabled := false
var storage: Array[String] = []
var audio: AudioStreamPlayer
var range_metres := 2.0
var intake_radius := 0.8

func setup(player: Node3D, folder: String) -> void:
	pilot = player
	audio = AudioStreamPlayer.new()
	audio.stream = preload("res://audio_loop.gd").prepare(_sound(folder),true,35)
	audio.volume_db = -16
	add_child(audio)

func reset() -> void:
	enabled = false; storage.clear()
	if audio != null: audio.stop()

func transfer_to(cargo: Dictionary) -> void:
	for item in storage: cargo[item] = int(cargo.get(item,0)) + 1
	storage.clear()

func _physics_process(_delta: float) -> void:
	var running: bool = enabled and pilot != null and pilot.active and pilot.controls_enabled and not pilot.dead
	if audio != null:
		if pilot != null and pilot.submarine_audio != null: audio.volume_db = -16 + float(pilot.submarine_audio.tuning.settings.master_volume)
		if running and audio.stream != null and not audio.playing: audio.play()
		elif not running and audio.playing: audio.stop()
	if not running or population == null or storage.size() >= CAPACITY: return
	for body in population.get_children():
		if not body is RigidBody3D or not body.has_method("pickup_item"): continue
		var item: String = body.pickup_item()
		if item.is_empty(): continue
		var offset: Vector3 = global_basis.orthonormalized().inverse() * (body.global_position - global_position)
		if offset.y > 0.15 or offset.y < -range_metres or Vector2(offset.x,offset.z).length() > intake_radius: continue
		var query := PhysicsRayQueryParameters3D.create(global_position,body.global_position,1,[pilot.get_rid(),body.get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): continue
		if offset.length() < 0.22:
			storage.append(item); body.dead = true; body.collision_layer = 0; body.hide(); body.queue_free()
			item_collected.emit(item)
			if storage.size() >= CAPACITY: break
		else:
			var direction: Vector3 = global_position - body.global_position
			var desired: Vector3 = direction.normalized() * minf(2.0,direction.length() * 4.0)
			body.apply_central_force((desired - body.linear_velocity) * body.mass * 8.0)

func _sound(folder: String) -> AudioStream:
	for replacement in preload("res://mod_registry.gd").candidates("audio.equipment.suckomat"):
		var stream := preload("res://legacy_audio.gd").load_file(replacement.path)
		if stream != null: return stream
	return preload("res://legacy_audio.gd").load_file(folder.path_join("WAVES/SUCK.RAW"))
