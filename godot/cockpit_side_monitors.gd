extends Node3D
## Fixed pilot-seat mounts for the full map and the downward camera.

const Display = preload("res://hud_display.gd")
const FACE_WIDTH := 0.056
const MAP_SCALE := 1.5
const DISTANCE := 0.084
const RENDER_SCALE := 3
var panels: Array[Node3D] = []
var displays: Array[Control] = []
var screens: Array[SubViewport] = []
var eye: Vector3
var face_sizes: Array[Vector2] = []
var seen: Array[bool] = [false, false]


func setup(hud: Node, neutral_eye: Vector3, render_layer: int) -> void:
	name = "SideMonitors"
	eye = neutral_eye
	var central: Control = hud.displays[2]
	var definition: Dictionary = hud.DEFINITIONS[2]
	var model_view := hud.instruments[2].get_node_or_null("ModelViewport") as SubViewport
	var aspect: float = definition.size.y / definition.size.x
	if model_view != null:
		var bounds: AABB = model_view.get_meta("instrument_bounds")
		aspect = bounds.size.y / bounds.size.x
	for index in range(2):
		var width := FACE_WIDTH * (MAP_SCALE if index == 0 else 1.0)
		face_sizes.append(Vector2(width, width * aspect))
		var panel := Node3D.new()
		panel.name = "FullMapMonitor" if index == 0 else "BottomCameraMonitor"
		add_child(panel)
		panels.append(panel)
		var display := Display.new()
		display.pilot = central.pilot
		display.map_data = central.map_data
		display.full_world = index == 0
		display.mouse_filter = Control.MOUSE_FILTER_IGNORE
		display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		displays.append(display)
		var content: SubViewport
		if model_view == null:
			content = hud._mount_sprite(panel, definition.size, render_layer, width / definition.size.x, RENDER_SCALE)
			display.frame = central.frame
			display.screen = Rect2(definition.screen.position * RENDER_SCALE, definition.screen.size * RENDER_SCALE)
		else:
			content = SubViewport.new()
			content.disable_3d = true
			content.size = Vector2i(definition.screen.size * RENDER_SCALE)
			content.render_target_update_mode = SubViewport.UPDATE_DISABLED
			panel.add_child(content)
			display.screen_only = true
			_mount_model(panel, model_view, content.get_texture(), render_layer, width)
		screens.append(content)
		display.size = Vector2(content.size)
		content.add_child(display)
		display.set_process(false)
		panel.hide()


func _mount_model(panel: Node3D, source: SubViewport, picture: Texture2D, render_layer: int, width: float) -> void:
	var original: Node3D = source.get_meta("instrument_model")
	var model := original.duplicate(0) as Node3D
	var bounds: AABB = source.get_meta("instrument_bounds")
	var rest: Transform3D = source.get_meta("instrument_transform")
	var normalizer := Basis.IDENTITY.scaled(Vector3.ONE * (width / bounds.size.x))
	var front := Vector3(bounds.get_center().x, bounds.get_center().y, bounds.end.z)
	model.transform = Transform3D(normalizer, -(normalizer * front)) * rest
	var screen: MeshInstance3D = model.get_node(original.get_path_to(source.get_meta("instrument_screen")))
	var material := screen.material_override.duplicate() as StandardMaterial3D
	material.albedo_texture = picture
	material.emission_texture = picture
	screen.material_override = material
	source.get_meta("crt_screen_materials").append(material)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = render_layer
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	panel.add_child(model)


func layout(viewport_size: Vector2, camera: Camera3D) -> void:
	var half_fov := deg_to_rad(camera.fov * 0.5)
	if camera.keep_aspect == Camera3D.KEEP_HEIGHT:
		half_fov = atan(tan(half_fov) * viewport_size.aspect())
	for index in range(2):
		var yaw := half_fov + atan2(face_sizes[index].x * 0.5, DISTANCE) + deg_to_rad(5)
		var x := -sin(yaw) if index == 0 else sin(yaw)
		var offset := Vector3(x * DISTANCE, -0.008, -cos(yaw) * DISTANCE)
		panels[index].transform = Transform3D(Basis.looking_at(-offset, Vector3.UP, true), eye + offset)


func refresh(camera: Camera3D, active: bool) -> void:
	var planes: Array[Plane] = []
	if active and is_instance_valid(camera): planes = camera.get_frustum()
	for index in range(2):
		var panel := panels[index]
		var in_view := not planes.is_empty() and _intersects_frustum(panel, face_sizes[index], planes)
		if seen[index] == in_view: continue
		seen[index] = in_view
		panel.visible = in_view
		displays[index].set_process(in_view)
		screens[index].render_target_update_mode = SubViewport.UPDATE_ALWAYS if in_view else SubViewport.UPDATE_DISABLED


func _intersects_frustum(panel: Node3D, face_size: Vector2, planes: Array[Plane]) -> bool:
	var half := face_size * 0.5
	var corners := PackedVector3Array([
		panel.to_global(Vector3(-half.x, -half.y, 0)), panel.to_global(Vector3(half.x, -half.y, 0)),
		panel.to_global(Vector3(-half.x, half.y, 0)), panel.to_global(Vector3(half.x, half.y, 0)),
	])
	for plane: Plane in planes:
		var outside := true
		for point in corners:
			if plane.distance_to(point) <= 0:
				outside = false
				break
		if outside: return false
	return true
