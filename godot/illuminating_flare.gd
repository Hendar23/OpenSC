extends Node3D
## Retail flare callbacks 00443260 / 00442ef0: FLR-1500 flares stick to
## scenery and remain lit offscreen; ordinary flares are view-dependent.
var tools: Node3D
var stationary := false
var velocity := Vector3.ZERO
var direction := Vector3.FORWARD
var age := 0.0
var stuck := false
var invisible_time := 0.0
var lamp: OmniLight3D
var glow: Sprite3D

func setup(context: Node3D, permanent: bool, point: Vector3, heading: Vector3) -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	tools = context; stationary = permanent; direction = heading
	global_position = point; velocity = tools.equipment.pilot.linear_velocity
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	lamp = OmniLight3D.new(); lamp.light_color = Color(1,0.82,0.52); lamp.omni_range = 8.0; lamp.light_energy = 8.0; add_child(lamp)
	glow = Sprite3D.new(); glow.texture = preload("res://clump_loader.gd")._load_texture(tools.folder,"FLARE","FLAREM",{})
	glow.pixel_size = 0.006; glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED; glow.no_depth_test = false; add_child(glow)
	var material := preload("res://natural_light.gd").billboard_material(glow.texture)
	material.set_shader_parameter("emission_color",Color.WHITE); material.set_shader_parameter("has_emission_texture",true); material.set_shader_parameter("emission_texture",glow.texture)
	glow.material_override = material
	reset_physics_interpolation()

func _physics_process(delta: float) -> void:
	age += delta
	if age >= 2000.0/25.0: queue_free(); return
	if not stuck:
		velocity = (velocity + direction*(0.0025/0.1*625.0)*delta)*pow(0.9,delta*25.0)
		var next := global_position+velocity*delta
		var query := PhysicsRayQueryParameters3D.create(global_position,next,13,[tools.equipment.pilot.get_rid()]); query.hit_back_faces = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): global_position = next
		else:
			global_position = hit.position+hit.normal*0.04
			if stationary: stuck = true; velocity = Vector3.ZERO
			else: velocity = velocity.bounce(hit.normal)*0.5; direction = direction.bounce(hit.normal)
	lamp.light_energy = 8.0 + sin(age*71.0)*0.7
	# The normal launcher's flare callback retires a flare once its draw/update
	# stamp is stale. Preserve that distinction without frame-rate dependence.
	var camera := get_viewport().get_camera_3d()
	if not stationary and age > 0.2 and camera != null:
		var seen := not camera.is_position_behind(global_position) and camera.is_position_in_frustum(global_position)
		invisible_time = 0.0 if seen else invisible_time+delta
		if invisible_time > 2.0/25.0: queue_free()
