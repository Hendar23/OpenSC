extends Control
## Mission guidance belongs to the main HUD, outside the cockpit refraction.
var game: Node
var jobs: Node

func _ready() -> void:
	# Pausing must clear the previous draw commands, as well as stop gameplay.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func target_body() -> CollisionObject3D:
	return jobs.target_body()

func target_point() -> Vector2:
	var target := target_body()
	if not is_instance_valid(target): return Vector2.INF
	return project_target(target,jobs.target_center(target))

func delivery_target_points() -> Array[Vector2]:
	var result: Array[Vector2] = []
	if not guidance_visible(): return result
	for target in game.game_dock.delivery_targets():
		var point := project_target(target,Vector3.ZERO)
		if point.is_finite(): result.append(point)
	return result

func guidance_visible() -> bool:
	return not (get_tree().paused or not game.pilot_mode or not game.pilot.active or game.pilot.dead or game.world_loading or game.dock_interface_active or game.map_open or game.front_end.menu_layer.visible)

func project_target(target: CollisionObject3D, center: Vector3) -> Vector2:
	if not guidance_visible(): return Vector2.INF
	var camera: Camera3D = game.camera
	var point: Vector3 = target.get_global_transform_interpolated() * center
	if camera.is_position_behind(point) or camera.global_position.distance_to(point) > camera.far: return Vector2.INF
	var projected := camera.unproject_position(point)
	if not get_viewport_rect().has_point(projected): return Vector2.INF
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,point,1,[target.get_rid(),game.pilot.get_rid()])
	if not camera.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): return Vector2.INF
	return projected

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var points := delivery_target_points()
	var point := target_point()
	if point.is_finite(): points.append(point)
	for marker_point in points: draw_marker(marker_point)

func draw_marker(point: Vector2) -> void:
	var scale_factor := get_viewport_rect().size.y / 480.0
	var half := 12.0 * scale_factor
	var length := 7.0 * scale_factor
	var tint := Color(0.1,1.0,0.2)
	for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
		var start: Vector2 = point + corner * half
		draw_line(start,start - Vector2(corner.x * length,0),tint,scale_factor,true)
		draw_line(start,start - Vector2(0,corner.y * length),tint,scale_factor,true)
