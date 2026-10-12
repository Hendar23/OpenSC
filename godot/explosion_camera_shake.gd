extends Node
## View offsets leave the follow-camera pose and HUD untouched.
var camera: Camera3D
var observer: Node3D
var strength := 0.0
var age := 0.0
func _ready() -> void:
	camera = get_parent() as Camera3D
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("explosion_camera_shake")
func blast(point: Vector3, diameter: float) -> void:
	if camera == null or not camera.current or get_tree().paused: return
	var radius := clampf(diameter * 6.0,6.0,24.0)
	var origin := observer.global_position if is_instance_valid(observer) else camera.global_position
	var falloff := clampf(1.0 - origin.distance_to(point) / radius,0,1)
	strength = minf(0.12,strength + falloff * falloff * clampf(diameter * 0.025,0.025,0.1))
func _process(delta: float) -> void:
	age += delta
	strength *= exp(-7.0 * delta)
	if strength < 0.0001: strength = 0
	camera.h_offset = sin(age * 83.0) * strength
	camera.v_offset = sin(age * 107.0 + 1.7) * strength * 0.7

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED and is_instance_valid(camera):
		strength = 0; camera.h_offset = 0; camera.v_offset = 0
