extends Node3D

const Assets = preload("res://clump_loader.gd")
const DEFAULTS := {"emission_rate":4.0, "lifetime":6.0, "start_size":0.25, "end_size":1.5, "rise_speed":0.6, "spread":0.15, "drift_x":0.0, "drift_z":0.0, "opacity":0.5}
const LIMITS := {"emission_rate":[0,40], "lifetime":[0.1,30], "start_size":[0.01,20], "end_size":[0.01,20], "rise_speed":[0,10], "spread":[0,5], "drift_x":[-10,10], "drift_z":[-10,10], "opacity":[0,1]}
const CAPACITY := 128
var tuning := DEFAULTS.duplicate()
var enabled := true
var puffs: Array[Dictionary] = []
var textures: Array[Texture2D] = []
var accumulator := 0.0
var rng := RandomNumberGenerator.new()

func configure(folder: String, values: Dictionary) -> void:
	enabled = bool(values.get("enabled",true))
	for key in DEFAULTS:
		tuning[key] = clampf(float(values.get(key,DEFAULTS[key])),LIMITS[key][0],LIMITS[key][1])
	# Editor duplicate/undo may duplicate children. Rebuild instance resources.
	for child in get_children(): child.free()
	puffs.clear(); textures.clear(); accumulator = 0.0
	var cache := {}
	for index in range(1,4):
		textures.append(Assets._load_texture(folder,"SMOKE%d" % index,"SMOKE%dM" % index,cache))
	rng.randomize()

func settings() -> Dictionary:
	var result := tuning.duplicate(); result.enabled = enabled
	return result

func clear() -> void:
	for puff in puffs: puff.node.free()
	puffs.clear(); accumulator = 0.0

func emission_origin() -> Vector3:
	return global_position

func _emit() -> void:
	if puffs.size() >= CAPACITY: return
	var puff := MeshInstance3D.new()
	var mesh := QuadMesh.new(); mesh.size = Vector2.ONE; puff.mesh = mesh
	# Use the shared fog/cave-aware billboard shader from the start. The game's
	# lighting pass otherwise replaces StandardMaterial3D while puffs are alive.
	var texture: Texture2D = textures[rng.randi_range(0,2)] if not textures.is_empty() else null
	var material := preload("res://natural_light.gd").billboard_material(texture)
	material.set_shader_parameter("has_texture",texture != null)
	material.set_shader_parameter("albedo_color",Color(0.65,0.65,0.65,1))
	material.set_shader_parameter("opacity",0.0)
	puff.material_override = material
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puff.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(puff); puff.top_level = true
	puff.global_position = emission_origin() + Vector3(rng.randf_range(-0.1,0.1),0,rng.randf_range(-0.1,0.1)) * tuning.spread
	puff.scale = Vector3.ONE * tuning.start_size
	# Rise and wind are world-space: the original factory markers have differing
	# orientations, including an inverted basis, but both plumes rise upwards.
	var velocity := Vector3(tuning.drift_x + rng.randf_range(-1,1) * tuning.spread,tuning.rise_speed * rng.randf_range(0.8,1.2),tuning.drift_z + rng.randf_range(-1,1) * tuning.spread)
	puffs.append({"node":puff,"age":0.0,"velocity":velocity})

func _process(delta: float) -> void:
	for index in range(puffs.size()-1,-1,-1):
		var puff: Dictionary = puffs[index]
		puff.age += delta
		var fraction: float = puff.age / tuning.lifetime
		if fraction >= 1.0:
			puff.node.free(); puffs.remove_at(index); continue
		puff.node.global_position += puff.velocity * delta
		puff.node.scale = Vector3.ONE * lerpf(tuning.start_size,tuning.end_size,fraction)
		puff.node.material_override.set_shader_parameter("opacity",tuning.opacity * minf(fraction * 8.0,1.0) * (1.0 - fraction))
	if not enabled or tuning.emission_rate <= 0.0: return
	accumulator += minf(delta,0.25) * tuning.emission_rate
	while accumulator >= 1.0:
		accumulator -= 1.0; _emit()
