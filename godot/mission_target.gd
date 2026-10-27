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
	if jobs.defection != null: return jobs.defection.target_body()
	if is_instance_valid(jobs.volcano): return jobs.volcano.target_body()
	if jobs.stage_three_remaining != null: return jobs.stage_three_remaining.target_body()
	if jobs.stage_three != null: return jobs.stage_three.target_body()
	if jobs.terrorists != null: return jobs.terrorists.target_body()
	if jobs.genocide != null: return jobs.genocide.target_body()
	if jobs.remaining != null: return jobs.remaining.target_body()
	if jobs.fishing != null: return jobs.fishing.target_body()
	if jobs.id == "stranded":
		if jobs.delivered_city == 0 and is_instance_valid(jobs.target) and not jobs.target.dead: return jobs.target
	elif jobs.id in ["breakout","breakout2"]:
		if not jobs.passengers and is_instance_valid(jobs.target) and not jobs.target.dead: return jobs.target.body
	elif jobs.id in ["spytrad","spytrad2"]:
		# Original 00490640 targets the scout first, then the revealed base.
		if not jobs.vents.is_empty():
			for vent in jobs.vents:
				if is_instance_valid(vent) and not vent.dead: return vent
		elif is_instance_valid(jobs.target) and not jobs.target.dead: return jobs.target.body
	return null

func target_point() -> Vector2:
	var target := target_body()
	if not is_instance_valid(target): return Vector2.INF
	if get_tree().paused or not game.pilot_mode or not game.pilot.active or game.pilot.dead or game.world_loading or game.dock_interface_active or game.map_open or game.front_end.menu_layer.visible: return Vector2.INF
	var camera: Camera3D = game.camera
	var center: Vector3 = target.get_meta("mission_target_center",Vector3.ZERO)
	if jobs.fishing != null: center = target.get_parent().get_node("Trader").bounds.get_center()
	elif jobs.stage_three_remaining == null and jobs.stage_three == null and jobs.genocide == null and jobs.remaining == null and jobs.id != "stranded" and is_instance_valid(jobs.target) and target == jobs.target.body: center = jobs.target.bounds.get_center()
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
	var point := target_point()
	if not point.is_finite(): return
	var scale_factor := get_viewport_rect().size.y / 480.0
	var half := 12.0 * scale_factor
	var length := 7.0 * scale_factor
	var tint := Color(0.1,1.0,0.2)
	for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
		var start: Vector2 = point + corner * half
		draw_line(start,start - Vector2(corner.x * length,0),tint,scale_factor,true)
		draw_line(start,start - Vector2(0,corner.y * length),tint,scale_factor,true)
