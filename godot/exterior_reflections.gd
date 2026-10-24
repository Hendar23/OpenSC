extends Node
## One low-resolution environment capture shared by every exterior canopy.
## Amortise the six faces over time rather than rendering six extra scenes/frame.
const DIRECTIONS := [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]
static var registered := false
var views: Array[SubViewport] = []
var cameras: Array[Camera3D] = []
var face := 0
var elapsed := 0.0
var capture_origin := Vector3.ZERO
var started := false
var enabled := true

static func ensure_globals() -> void:
	if registered: return
	registered = true
	RenderingServer.global_shader_parameter_add("osc_exterior_enabled",RenderingServer.GLOBAL_VAR_TYPE_BOOL,true)
	RenderingServer.global_shader_parameter_add("osc_exterior_ready",RenderingServer.GLOBAL_VAR_TYPE_BOOL,false)
	for index in range(6):
		RenderingServer.global_shader_parameter_add("osc_exterior_face_%d" % index,RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D,null)

func setup(world: World3D, active: bool = true) -> void:
	ensure_globals()
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("exterior_canopy_reflections")
	enabled = not active
	set_enabled(active)
	RenderingServer.global_shader_parameter_set("osc_exterior_ready",false)
	# Dummy rendering cannot supply images; keep the ordinary lit-glass fallback.
	if DisplayServer.get_name() == "headless": return
	for index in range(6):
		var view := SubViewport.new(); view.name = "CanopyFace%d" % index
		view.set_meta("exterior_capture",true)
		view.size = Vector2i(128,128); view.world_3d = world
		view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		view.positional_shadow_atlas_size = 0; view.mesh_lod_threshold = 8.0
		view.canvas_cull_mask = 0; add_child(view); views.append(view)
		var camera := Camera3D.new(); camera.fov = 90; camera.near = 0.15; camera.far = 30.0
		# World layer only: exclude player (2), glass-bearing meshes (1 << 17)
		# and the camera-local cockpit. No render target can sample itself.
		camera.cull_mask = 1
		view.add_child(camera); camera.current = true; cameras.append(camera)
		RenderingServer.global_shader_parameter_set("osc_exterior_face_%d" % index,view.get_texture())

func set_enabled(active: bool) -> void:
	if enabled == active and is_processing() == active: return
	enabled = active
	set_process(active)
	RenderingServer.global_shader_parameter_set("osc_exterior_enabled",active)
	RenderingServer.global_shader_parameter_set("osc_exterior_ready",false)
	face = 0; elapsed = 0.0; started = false
	for view in views: view.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _process(delta: float) -> void:
	if not enabled or views.is_empty(): return
	elapsed += delta
	if elapsed < 0.1: return
	elapsed = 0.0
	var source := get_viewport().get_camera_3d()
	if source == null: return
	# All six faces in a cycle share an origin; fast camera movement cannot
	# leave different faces sampling unrelated rooms.
	if face == 0: capture_origin = source.global_position
	var direction: Vector3 = DIRECTIONS[face]
	var up := Vector3.BACK if absf(direction.y) > 0.5 else Vector3.UP
	cameras[face].global_transform = Transform3D(Basis.looking_at(direction,up),capture_origin)
	views[face].render_target_update_mode = SubViewport.UPDATE_ONCE
	if started: RenderingServer.global_shader_parameter_set("osc_exterior_ready",true)
	face = (face + 1) % 6
	if face == 0: started = true

func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("osc_exterior_ready",false)
