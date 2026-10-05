extends RefCounted

const STICK_DEADZONE := 0.15
const TRIGGER_DEADZONE := 0.05

static func stick(value: Vector2) -> Vector2:
	var length := minf(value.length(), 1.0)
	if length <= STICK_DEADZONE: return Vector2.ZERO
	return value.normalized() * (length - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)

static func trigger(value: float) -> float:
	return clampf((value - TRIGGER_DEADZONE) / (1.0 - TRIGGER_DEADZONE), 0.0, 1.0)

static func from_axes(left: Vector2, right: Vector2, reverse: float, forward: float) -> Vector4:
	left = stick(left)
	right = stick(right)
	# Aircraft pitch: pulling the left stick back raises the nose.
	# The right stick keeps its direct up/down pod thrust convention.
	return Vector4(trigger(forward) - trigger(reverse), -right.y, -left.x, left.y)

static func read() -> Vector4:
	preload("res://input_bindings.gd").install()
	var result := Vector4(
		float(Input.is_action_pressed("thrust_forward")) - float(Input.is_action_pressed("thrust_reverse")),
		float(Input.is_action_pressed("thrust_up")) - float(Input.is_action_pressed("thrust_down")),
		float(Input.is_action_pressed("turn_left")) - float(Input.is_action_pressed("turn_right")),
		float(Input.is_action_pressed("pitch_up")) - float(Input.is_action_pressed("pitch_down")))
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		var pad := pads[0]
		result += from_axes(Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y)),
			Vector2(0.0, Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y)),
			Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_LEFT), Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT))
	return Vector4(clampf(result.x, -1, 1), clampf(result.y, -1, 1), clampf(result.z, -1, 1), clampf(result.w, -1, 1))
