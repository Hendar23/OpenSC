extends Node3D
## The cockpit and optics use the interpolated hull pose. Only the eye can turn.
const RENDER_LAYER := preload("res://first_person_cockpit.gd").RENDER_LAYER
const Assets = preload("res://clump_loader.gd")
const Pilot = preload("res://submarine_controller.gd")
const CockpitRim = preload("res://cockpit_rim.gd")
const STUDY_SCALE := 6.0
const DOME_RADII := Vector3(2.71, 1.61, 2.4)
const EYE_HOME := Vector3(0.0, 0.003, -0.150)
const DOME_CENTRE := EYE_HOME - Vector3(0.0, 0.0, 2.03) / STUDY_SCALE
const OVERSCAN := 1.65
const DEFAULTS := {"wear": 7.0, "bend": 0.85, "spread": 0.24, "thickness": 0.07,
	"sideways": 0.0, "height": 0.0, "forward": 0.73, "reflections": false}
const INSTRUMENT_REFERENCE_EYE := EYE_HOME + Vector3(0.0, 0.0, -0.73 / STUDY_SCALE)
const SLIDERS := [
	["sideways", "Camera sideways", -0.55, 0.55, 0.01],
	["height", "Camera height", -0.40, 0.40, 0.01],
	["forward", "Camera forward", -0.15, 1.10, 0.01],
	["wear", "Perspex wear", 0.0, 8.0, 0.05],
	["bend", "Refraction bend", 0.0, 0.85, 0.01],
	["spread", "Refraction spread", 0.0, 1.0, 0.01],
	["thickness", "Perspex thickness", 0.02, 0.40, 0.005],
]
var game: Node3D
var hull: Node3D
var glass := ShaderMaterial.new()
var optics := ShaderMaterial.new()
var pane: MeshInstance3D
var source_view: SubViewport
var source_camera: Camera3D
var normal_mask := 0
var redirected := false
var reflection_capture: Node


static func prepare_hull(active: Node3D, folder: String) -> Node3D:
	var original := not active.has_meta("asset_mod")
	var model: Node3D
	if original or _supports_cockpit(active):
		model = active.duplicate(0) as Node3D
	else:
		original = true
		model = Assets.load_original_submarine(folder.path_join("CLUMPS/SUB.DFF"))
		if model == null: return null
		model.rotation.y = PI
		model.scale *= Pilot.VISUAL_SCALE
	# A cockpit copy is visual only. Imported lights, cameras and physics
	# belong to the actual replacement model.
	for type in ["Camera3D", "Light3D", "CollisionObject3D", "AudioStreamPlayer3D"]:
		for node in model.find_children("*", type, true, false):
			if is_instance_valid(node): node.free()
	var round_legacy := original or str(model.get_meta("asset_source", "")).get_extension().to_lower() == "dff"
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		_remove_glazing(mesh, round_legacy)
		mesh.layers = RENDER_LAYER
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return model


static func _supports_cockpit(model: Node3D) -> bool:
	var interior := false
	var glazing := false
	for visual: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if visual.mesh == null: continue
		for i in range(visual.mesh.get_surface_count()):
			var material := visual.get_active_material(i)
			if material == null: continue
			if material.get_meta("exterior_canopy", false):
				glazing = true
				# A legacy replacement can use the retail console topology.
				if not model.get_meta("modern_model", false):
					interior = interior or not CockpitRim.find_edges(visual.mesh, i).is_empty()
			elif material.get_meta("cockpit_interior", false):
				interior = true
	return glazing and interior


func setup(context: Node3D, cockpit_hull: Node3D) -> void:
	game = context
	name = "PerspexCockpit"
	top_level = true
	# The follow camera supplies the already-interpolated hull pose every
	# render frame. Inheriting the pilot's interpolation would apply it twice.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	hull = cockpit_hull
	if hull == null: return
	add_child(hull)
	game.natural_light.attach(hull)

	var shell := _make_shell()
	glass.shader = preload("res://perspex_wear.gdshader")
	glass.render_priority = 2
	glass.set_shader_parameter("wear_mask", preload("res://game_assets/effects/perspex_wear.webp"))
	_add_surface(shell, glass)
	optics.shader = preload("res://perspex_refraction.gdshader")
	optics.set_shader_parameter("dome_radii", DOME_RADII)
	optics.set_shader_parameter("overscan", OVERSCAN)
	pane = _add_surface(shell, optics)
	pane.hide()
	if DisplayServer.get_name() != "headless": _setup_source()
	apply_tuning()


static func _remove_glazing(mesh: MeshInstance3D, round_legacy: bool = true) -> void:
	var glazing := -1
	var remaster_console := -1
	for i in range(mesh.mesh.get_surface_count()):
		var material := mesh.get_active_material(i)
		if material != null and material.get_meta("exterior_canopy", false):
			glazing = i
		elif material != null and material.get_meta("cockpit_interior", false) and material.resource_name == "Canopy interior":
			remaster_console = i
	if glazing == -1 and remaster_console == -1: return

	var source := mesh.mesh as ArrayMesh
	if source == null: return
	var rim := {}
	if source.get_blend_shape_count() == 0:
		if round_legacy: rim = CockpitRim.find_edges(source, glazing)
		elif remaster_console != -1: rim = CockpitRim.find_edges(source, glazing, remaster_console)
	var opaque := ArrayMesh.new()
	opaque.blend_shape_mode = source.blend_shape_mode
	for shape in range(source.get_blend_shape_count()):
		opaque.add_blend_shape(source.get_blend_shape_name(shape))
	for i in range(source.get_surface_count()):
		var material := mesh.get_active_material(i)
		if material != null and material.get_meta("exterior_canopy", false): continue
		var arrays := source.surface_get_arrays(i)
		if not rim.is_empty() and (round_legacy or i == remaster_console):
			arrays = CockpitRim.round_edges(arrays, rim)
		opaque.add_surface_from_arrays(source.surface_get_primitive_type(i), arrays, source.surface_get_blend_shape_arrays(i))
		opaque.surface_set_material(opaque.get_surface_count() - 1, material)
		opaque.surface_set_name(opaque.get_surface_count() - 1, source.surface_get_name(i))
	for i in range(source.get_surface_count()): mesh.set_surface_override_material(i, null)
	mesh.material_override = null
	mesh.mesh = opaque


func _add_surface(shell: ArrayMesh, material: Material) -> MeshInstance3D:
	var surface := MeshInstance3D.new()
	surface.mesh = shell
	surface.material_override = material
	surface.position = DOME_CENTRE
	surface.scale = Vector3.ONE / STUDY_SCALE
	surface.layers = RENDER_LAYER
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)
	return surface


func _setup_source() -> void:
	source_view = SubViewport.new()
	source_view.world_3d = get_world_3d()
	source_view.use_hdr_2d = true
	source_view.canvas_cull_mask = 0
	source_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(source_view)
	source_camera = Camera3D.new()
	source_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	source_view.add_child(source_camera)
	source_camera.make_current()
	optics.set_shader_parameter("scene_color", source_view.get_texture())


func enabled() -> bool:
	return hull != null and game.first_person and game.front_end.gameplay_menu.cockpit_3d_enabled


func apply_tuning() -> void:
	if hull == null: return
	var settings: Dictionary = game.cockpit_tuning
	glass.set_shader_parameter("wear", settings.wear)
	for key in ["bend", "spread", "thickness"]: optics.set_shader_parameter(key, settings[key])


func eye_position() -> Vector3:
	var settings: Dictionary = game.cockpit_tuning
	return EYE_HOME + Vector3(settings.sideways, settings.height, -settings.forward) / STUDY_SCALE


func scene_mask() -> int:
	return normal_mask if redirected else game.camera.cull_mask


func stop() -> void:
	if redirected and is_instance_valid(game.camera): game.camera.cull_mask = normal_mask
	redirected = false
	if source_view != null: source_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if game.game_camera.freelook: game.game_camera.cancel_freelook()
	if is_instance_valid(game.cockpit_hud) and game.cockpit_hud.is_inside_tree(): game.cockpit_hud.release_mounted_instruments()
	hide()


func refresh() -> void:
	var active: bool = (enabled() and game.pilot_mode and not game.pilot.dead and not game.world_loading
		and not game.loading_save and not game.map_open and not game.dock_interface_active
		and not game.front_end.menu_layer.visible and not get_tree().paused and game.camera.current
		and game.docking != null and game.docking.stage != game.Docking.Stage.DOCKED
		and (game.fmv == null or not game.fmv.active))
	if not active:
		if visible: stop()
		return
	show()
	game.cockpit_hud.mount_instruments(self, INSTRUMENT_REFERENCE_EYE, RENDER_LAYER)
	var bend: float = game.cockpit_tuning.bend
	if source_view != null and bend > 0.0:
		if not redirected: normal_mask = game.camera.cull_mask
		redirected = true
		game.camera.cull_mask = RENDER_LAYER
		_update_source()
	elif redirected:
		game.camera.cull_mask = normal_mask
		source_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		redirected = false
	pane.visible = redirected


func _update_source() -> void:
	var camera: Camera3D = game.camera
	var viewport := camera.get_viewport()
	var size := Vector2i((viewport.get_visible_rect().size * OVERSCAN).ceil()).max(Vector2i(2, 2))
	if source_view.size != size: source_view.size = size
	source_view.scaling_3d_scale = viewport.scaling_3d_scale
	source_view.scaling_3d_mode = viewport.scaling_3d_mode
	source_view.msaa_3d = viewport.msaa_3d
	source_view.screen_space_aa = viewport.screen_space_aa
	source_view.positional_shadow_atlas_size = viewport.positional_shadow_atlas_size
	source_camera.near = camera.near
	source_camera.far = camera.far
	source_camera.keep_aspect = camera.keep_aspect
	source_camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(camera.fov) * 0.5) * OVERSCAN))
	source_camera.environment = camera.environment
	source_camera.attributes = camera.attributes
	source_camera.cull_mask = normal_mask & ~RENDER_LAYER
	source_camera.global_transform = camera.global_transform
	source_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _process(delta: float) -> void:
	refresh()
	if not visible: return
	glass.set_shader_parameter("key_direction", game.sun.global_basis.z)
	glass.set_shader_parameter("key_energy", game.sun.light_energy)
	if game.cockpit_tuning.reflections and reflection_capture == null and source_view != null:
		reflection_capture = preload("res://perspex_reflections.gd").new()
		add_child(reflection_capture)
		reflection_capture.setup(game.camera, get_world_3d(), scene_mask() & ~RENDER_LAYER, glass)
	if reflection_capture != null: reflection_capture.tick(delta, game.cockpit_tuning.reflections)


func _exit_tree() -> void:
	if is_instance_valid(game): stop()


func _make_shell() -> ArrayMesh:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	const RINGS := 64
	const SECTORS := 112
	for row in range(RINGS + 1):
		var theta := float(row) / RINGS * PI
		for sector in range(SECTORS):
			var radial := Vector2.from_angle(float(sector) / SECTORS * TAU)
			var unit := Vector3(radial.x * sin(theta), radial.y * sin(theta), -cos(theta))
			builder.set_normal((unit / DOME_RADII).normalized())
			builder.set_uv(radial * (0.5 * sin(theta * 0.5)) + Vector2(0.5, 0.5))
			builder.add_vertex(unit * DOME_RADII)
	for row in range(RINGS):
		for sector in range(SECTORS):
			var current := row * SECTORS + sector
			var next := row * SECTORS + (sector + 1) % SECTORS
			if row > 0:
				builder.add_index(current)
				builder.add_index(next)
				builder.add_index(current + SECTORS)
			if row < RINGS - 1:
				builder.add_index(next)
				builder.add_index(next + SECTORS)
				builder.add_index(current + SECTORS)
	return builder.commit()
