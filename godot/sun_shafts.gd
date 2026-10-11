extends Node3D
## Small, recycled patches of surface sunlight around the active camera.
const PATCH_LIMIT := 8
const MAX_REACH := 45.0
var game: Node3D
var enabled := true
var brightness := 1.0
var random := RandomNumberGenerator.new()
var patches: Array[Dictionary] = []
var cursor := 0
var elapsed := 0.0

func setup(owner_game: Node3D) -> void:
	game = owner_game; process_mode = Node.PROCESS_MODE_ALWAYS
	random.randomize()
	for index in PATCH_LIMIT:
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new(); mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new(); material.shader = preload("res://sun_shafts.gdshader")
		mesh.material_override = material; add_child(mesh); mesh.hide()
		patches.append({"node":mesh,"material":material,"age":0.0,"lifetime":0.0,"source":Vector3.ZERO,"width":3.0,"blocked":false})

func set_enabled(value: bool) -> void:
	enabled = value
	set_physics_process(enabled)
	if not enabled:
		for patch in patches: patch.node.hide(); patch.lifetime = 0.0

func _physics_process(delta: float) -> void:
	if game == null or not enabled: return
	var menu: bool = game.menu_backdrop != null and game.menu_backdrop.active
	if get_tree().paused and not menu: return
	var view: Camera3D = game.menu_backdrop.view if menu else game.camera
	var cycle: RefCounted = game.menu_backdrop.daylight if menu else game.day_night
	var sun_direction: Vector3 = cycle.sun_direction()
	var surface: float = game.world_root.get_meta("surface_height")
	var depth: float = surface - view.global_position.y
	var depth_limit: float = game.natural_light.settings.sun_depth + game.natural_light.settings.sun_falloff
	if sun_direction.y < 0.18 or depth > depth_limit or depth < 0.0:
		for patch in patches: patch.node.hide(); patch.lifetime = 0.0
		return
	for patch in patches:
		patch.age += delta
		var fade: float = smoothstep(0.0,2.0,patch.age) * (1.0 - smoothstep(patch.lifetime - 3.0,patch.lifetime,patch.age)) if patch.lifetime > 0 else 0.0
		patch.material.set_shader_parameter("strength",brightness * fade * cycle.daylight() * smoothstep(0.18,0.5,sun_direction.y))
		patch.material.set_shader_parameter("light_color",game.sun.light_color)
		patch.node.visible = fade > 0.0 and not patch.blocked
	# One patch check per tick interval: no frame performs a burst of terrain rays.
	elapsed += delta
	if elapsed < 0.08: return
	elapsed = 0.0
	var patch: Dictionary = patches[cursor]; cursor = (cursor + 1) % PATCH_LIMIT
	var at_camera_depth: Vector3 = patch.source - sun_direction * (depth / sun_direction.y)
	if patch.age >= patch.lifetime or at_camera_depth.distance_to(view.global_position) > 45.0:
		var point: Vector3 = view.global_position - view.global_basis.z * random.randf_range(6.0,22.0)
		point += view.global_basis.x * random.randf_range(-14.0,14.0)
		point.y = minf(point.y,surface - 1.0)
		patch.source = point + sun_direction * ((surface - point.y) / sun_direction.y)
		patch.age = 0.0; patch.lifetime = random.randf_range(12.0,22.0)
		patch.width = random.randf_range(2.0,4.5)
		patch.material.set_shader_parameter("seed",random.randf() * 100.0)
	var direction := -sun_direction
	var pose := Basis.looking_at(-direction,Vector3.FORWARD)
	var reach := MAX_REACH
	# Conservative samples across the patch prevent sunlight continuing through
	# buildings/terrain. Scene-depth clipping also handles foreground objects.
	for offset in [Vector3.ZERO,pose.x * patch.width * 0.35,-pose.x * patch.width * 0.35]:
		var start: Vector3 = patch.source + offset + sun_direction * 0.05
		var query := PhysicsRayQueryParameters3D.create(start,start + direction * MAX_REACH,1)
		query.hit_back_faces = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty(): reach = minf(reach,start.distance_to(hit.position))
	patch.blocked = reach < 0.2
	reach = maxf(0.05,reach)
	patch.node.transform = Transform3D(pose,patch.source + direction * reach * 0.5)
	patch.node.mesh.size = Vector3(patch.width,patch.width,reach)
	patch.material.set_shader_parameter("beam_length",reach)
	patch.material.set_shader_parameter("beam_width",patch.width)
	patch.material.set_shader_parameter("surface_height",surface)
	patch.material.set_shader_parameter("depth_start",float(game.natural_light.settings.sun_depth))
	patch.material.set_shader_parameter("depth_end",depth_limit)
	patch.material.set_shader_parameter("view_range",minf(view.far,game.fog_visibility))
