extends Node3D
## Placeable, bounded seabed emitter. Uses the same mod-aware bubbles as wakes.
const DEFAULTS := {"emission_rate":2.0,"lifetime":20.0,"start_size":0.08,"end_size":0.16,"rise_speed":0.8,"spread":0.08,"drift_x":0.0,"drift_z":0.0,"opacity":0.7}
const LIMITS := {"emission_rate":[0,40],"lifetime":[0.1,60],"start_size":[0.01,2],"end_size":[0.01,4],"rise_speed":[0.01,10],"spread":[0,5],"drift_x":[-10,10],"drift_z":[-10,10],"opacity":[0,1]}
var tuning := DEFAULTS.duplicate()
var enabled := true
var renderer: Node3D
func configure(folder: String, values: Dictionary) -> void:
	add_to_group("ambient_bubbles")
	enabled = bool(values.get("enabled",true))
	for key in DEFAULTS: tuning[key] = clampf(float(values.get(key,DEFAULTS[key])),LIMITS[key][0],LIMITS[key][1])
	if renderer != null: renderer.free()
	renderer = preload("res://propeller_bubbles.gd").new(); renderer.capacity = 128; add_child(renderer)
	renderer.configure(preload("res://clump_loader.gd")._load_texture(folder,"BUBBLE","BUBBLEM",{}))
	var world: Node = self
	while world != null and not world.has_meta("surface_height"): world = world.get_parent()
	if world != null: renderer.surface_height = float(world.get_meta("surface_height"))
func settings() -> Dictionary:
	return tuning.merged({"enabled":enabled})
func _physics_process(delta: float) -> void:
	if renderer == null: return
	var camera := get_viewport().get_camera_3d()
	if not enabled or (camera != null and camera.global_position.distance_squared_to(global_position) > 6400):
		renderer.clear(); return
	var before: int = renderer.particles.size()
	renderer.emit_from(0,global_position,Vector3.ZERO,1.0,tuning.emission_rate,delta)
	for index in range(before,renderer.particles.size()):
		var particle: Dictionary = renderer.particles[index]
		particle.position += Vector3(randf_range(-1,1),0,randf_range(-1,1)) * float(tuning.spread)
		particle.drift = Vector3(tuning.drift_x,0,tuning.drift_z)
		particle.rise = tuning.rise_speed
		particle.size = tuning.start_size
		particle.end_size = tuning.end_size
		particle.lifetime = tuning.lifetime
		particle.opacity = tuning.opacity
