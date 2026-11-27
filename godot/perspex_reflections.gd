extends Node
## Gather a complete second cube one face per frame before blending it in.
const FOV := 98.0
const BLEND_TIME := 0.095
const DIRECTIONS := {
	"px": Vector3.RIGHT, "nx": Vector3.LEFT,
	"py": Vector3.UP, "ny": Vector3.DOWN,
	"pz": Vector3.BACK, "nz": Vector3.FORWARD,
}

var source: Camera3D
var glass: ShaderMaterial
var banks: Array[Array] = []
var bank := 0
var face := 0
var blend := 0.0
var origin := Vector3.ZERO
var warmed := false


func setup(camera: Camera3D, world: World3D, mask: int, material: ShaderMaterial) -> void:
	source = camera
	glass = material
	glass.set_shader_parameter("reflection_projection_scale", 0.5 / tan(deg_to_rad(FOV * 0.5)))
	for i in range(2):
		var views: Array[SubViewport] = []
		for key in DIRECTIONS:
			var view := SubViewport.new()
			view.set_meta("exterior_capture", true)
			view.size = Vector2i(256, 256)
			view.world_3d = world
			view.canvas_cull_mask = 0
			view.positional_shadow_atlas_size = 0
			view.mesh_lod_threshold = 4.0
			view.render_target_update_mode = SubViewport.UPDATE_DISABLED
			add_child(view)
			views.append(view)
			var direction: Vector3 = DIRECTIONS[key]
			var up := Vector3.BACK if absf(direction.y) > 0.5 else Vector3.UP
			var eye := Camera3D.new()
			eye.fov = FOV
			eye.far = minf(source.far, 40.0)
			eye.cull_mask = mask
			eye.basis = Basis.looking_at(direction, up)
			view.add_child(eye)
			eye.make_current()
		banks.append(views)
	_bind()


func _bind() -> void:
	var i := 0
	for key in DIRECTIONS:
		var current: SubViewport = banks[bank][i]
		var pending: SubViewport = banks[1 - bank][i]
		glass.set_shader_parameter("reflection_" + key, current.get_texture())
		glass.set_shader_parameter("next_reflection_" + key, pending.get_texture())
		i += 1


func tick(delta: float, enabled: bool) -> void:
	glass.set_shader_parameter("reflection_ready", enabled and warmed)
	if not enabled: return
	if face == DIRECTIONS.size():
		blend = minf(1.0, blend + delta / BLEND_TIME) if warmed else 1.0
		if blend >= 1.0:
			bank = 1 - bank
			face = 0
			blend = 0.0
			warmed = true
			_bind()
		glass.set_shader_parameter("reflection_blend", blend)
		return
	if face == 0:
		if warmed and origin.distance_squared_to(source.global_position) < 0.0225: return
		origin = source.global_position
	var view: SubViewport = banks[1 - bank][face]
	view.get_camera_3d().global_position = origin
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	face += 1
