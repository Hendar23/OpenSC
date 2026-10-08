extends Node3D
const Document = preload("res://map_document.gd")
var fish: CharacterBody3D
var settings := {}
var target: Node3D
var threat: Node3D
var scan_timer := 0.0
var bite_timer := 0.0
var weapon: Node3D
var sound: AudioStreamPlayer3D
var blood: Node3D
var blood_timer := 0.0

func configure(owner_fish: CharacterBody3D, species: Dictionary) -> void:
	fish = owner_fish; settings = Document.creature_combat(species)
	scan_timer = fish.rng.randf_range(0,0.2)

func perceive(delta: float) -> void:
	bite_timer = maxf(0,bite_timer - delta)
	scan_timer -= delta
	if scan_timer > 0: return
	scan_timer = 0.2
	target = null; threat = null
	if fish.population == null or settings.food_role == "neutral": return
	var nearest: float = fish.detection_distance * fish.detection_distance
	for other in fish.population.nearby_creatures(fish.global_position,fish.detection_distance):
		if other == fish or not alive(other) or other.combat == null: continue
		var distance: float = fish.global_position.distance_squared_to(other.global_position)
		if distance > nearest: continue
		if settings.food_role == "predator" and other.combat.settings.food_role == "prey":
			target = other; nearest = distance
		elif settings.food_role == "prey" and other.combat.settings.food_role == "predator":
			threat = other; nearest = distance

static func alive(body: Node3D) -> bool:
	if not is_instance_valid(body) or body.is_queued_for_deletion() or bool(body.get("dead")): return false
	if not body.get_meta("wildlife_awake",true): return false
	return body.is_physics_processing()

func attack(delta: float) -> void:
	blood_timer = maxf(0,blood_timer - delta)
	if fish.population != null and target == fish.population.player:
		if not is_instance_valid(target) or not bool(target.get("active")) or not bool(target.get("controls_enabled")) or fish.response not in ["attack","defend"] or (fish.response == "defend" and fish.defense_timer <= 0) or fish.global_position.distance_to(target.global_position) >= fish.detection_distance:
			target = null
	if not alive(target) or fish.fleeing or fish.startle_timer > 0:
		_stop_weapon(); return
	var offset := target.global_position - fish.global_position
	if offset.length_squared() < 0.000001 or fish.direction.dot(offset.normalized()) < 0.65:
		_stop_weapon(); return
	var start: Vector3 = fish.global_position + fish.direction * fish.radius * 0.7
	var query := PhysicsRayQueryParameters3D.create(start,target.global_position,15,[fish.get_rid()])
	query.hit_back_faces = true
	var hit := fish.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.get("collider") != target:
		_stop_weapon(); return
	if settings.has_zapper and start.distance_to(hit.position) <= float(settings.zapper_range):
		target.take_damage(float(settings.zapper_damage) * delta,fish.global_position)
		_hit_feedback(hit)
		_show_weapon(start,hit.position)
		return
	_stop_weapon()
	var target_radius := float(target.get("radius")) if target.get("radius") != null else (float(target.collision_height()) * 0.5 if target.has_method("collision_height") else 0.0)
	if offset.length() <= fish.radius + target_radius + float(settings.bite_range) and bite_timer <= 0:
		bite_timer = float(settings.attack_interval)
		target.take_damage(float(settings.bite_damage),fish.global_position)
		_hit_feedback(hit)

func _hit_feedback(hit: Dictionary) -> void:
	if target.get("death_frames") == null or blood_timer > 0: return
	if blood == null: blood = preload("res://creature_hit.gd").new(); add_child(blood)
	var gore: Dictionary = preload("res://creature_death.gd").settings
	blood.emit_hit(hit.position,hit.normal,target.death_frames,float(gore.gore_amount),float(gore.gore_lifetime),float(gore.gore_settle_speed))
	blood_timer = 0.15

func _show_weapon(start: Vector3, end: Vector3) -> void:
	if weapon == null:
		# Share the player's animated, repeating crackle ribbon without its input or mounting logic.
		weapon = load("res://submarine_weapons.gd").new()
		weapon.pilot = fish; weapon.frames = fish.population.zapper_frames
		weapon.settings.beam_width = clampf(fish.radius * 0.3,0.025,0.18)
		weapon.beam = MeshInstance3D.new(); weapon.beam.top_level = true; weapon.beam.mesh = ArrayMesh.new()
		weapon.beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		weapon.material = StandardMaterial3D.new()
		weapon.material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		weapon.material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		weapon.material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		weapon.material.cull_mode = BaseMaterial3D.CULL_DISABLED; weapon.material.texture_repeat = true
		weapon.beam.material_override = weapon.material; weapon.add_child(weapon.beam)
		weapon.impact = Sprite3D.new(); weapon.add_child(weapon.impact); weapon.impact.hide()
		add_child(weapon); weapon.set_physics_process(false)
		sound = AudioStreamPlayer3D.new(); sound.stream = fish.population.zapper_sound
		sound.volume_db = -16; sound.unit_size = 3; sound.max_distance = 30; add_child(sound)
	weapon.camera = get_viewport().get_camera_3d()
	weapon.firing = weapon.camera != null and not weapon.frames.is_empty()
	weapon.beam.visible = weapon.firing
	weapon.beam_start = start; weapon.beam_end = end
	preload("res://explosion_audio.gd").apply(sound,0.0,"wildlife_zapper_volume")
	if sound.stream != null and not sound.playing: sound.play()

func _stop_weapon() -> void:
	if weapon != null: weapon.firing = false; weapon.beam.hide()
	if sound != null: sound.stop()

func _process(_delta: float) -> void:
	if fish == null or fish.dead or not fish.is_physics_processing(): _stop_weapon()
