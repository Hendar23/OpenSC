extends Control
## Retail homing sight, drawn over the main view rather than inside the CRT.
var arsenal: Node3D
var frame: Texture2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void: queue_redraw()

func _draw() -> void:
	if not is_instance_valid(arsenal) or get_tree().paused: return
	var weapons: Node3D = arsenal.weapons
	var pilot: Node3D = weapons.pilot
	if not pilot.active or not pilot.controls_enabled or pilot.dead or pilot.remote_controlled or weapons.current().get("id","") != "homers": return
	var target: Node3D = arsenal.homing_target
	if not is_instance_valid(target) or target.get("dead") == true: return
	var camera: Camera3D = weapons.camera
	var point: Vector3 = target.get_global_transform_interpolated()*Vector3(target.get_meta("mission_target_center",Vector3.ZERO))
	if camera.is_position_behind(point): return
	var center := camera.unproject_position(point)
	if not get_viewport_rect().has_point(center): return
	var scale_factor := get_viewport_rect().size.y/480.0
	if frame != null: draw_texture_rect(frame,Rect2(center-Vector2.ONE*18*scale_factor,Vector2.ONE*36*scale_factor),false)
