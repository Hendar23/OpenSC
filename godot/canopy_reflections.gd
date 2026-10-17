extends Node
## Scene captures shared by all canopy glass meshes; updated with every frame.
const DIRECTIONS := [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]
var views: Array[SubViewport] = []
var cameras: Array[Camera3D] = []
var materials: Array[ShaderMaterial] = []
var warmed := false

func setup(world: World3D, glass: Array[ShaderMaterial], source: Camera3D) -> void:
	materials = glass
	for index in range(6):
		var view := SubViewport.new(); view.name = "ReflectionFace%d" % index
		view.size = Vector2i(256,256); view.world_3d = world
		view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		view.positional_shadow_atlas_size = 0; view.mesh_lod_threshold = 4.0
		view.canvas_cull_mask = 0; add_child(view); views.append(view)
		var camera := Camera3D.new(); camera.fov = 90; camera.near = 0.04
		camera.far = minf(source.far,40.0); camera.cull_mask = source.cull_mask & ~(2 | (1 << 19))
		view.add_child(camera); camera.current = true; cameras.append(camera)
		for material in materials: material.set_shader_parameter("reflection_face_%d" % index,view.get_texture())

func configure(resolution: int, distance: float, source: Camera3D) -> void:
	for index in range(views.size()):
		views[index].size = Vector2i(resolution,resolution)
		cameras[index].far = minf(source.far,distance)

func update_capture(_delta: float, active: bool, source: Camera3D) -> void:
	if not active:
		for view in views: view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		warmed = false
		for material in materials: material.set_shader_parameter("scene_reflections_ready",false)
		return
	for index in range(6):
		var direction: Vector3 = DIRECTIONS[index]
		var up := Vector3.BACK if absf(direction.y) > 0.5 else Vector3.UP
		cameras[index].global_transform = Transform3D(Basis.looking_at(direction,up),source.global_position)
		views[index].render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for material in materials: material.set_shader_parameter("scene_reflections_ready",warmed)
	warmed = true
