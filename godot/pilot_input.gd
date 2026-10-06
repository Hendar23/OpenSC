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
	var bindings = preload("res://input_bindings.gd")
	bindings.install()
	return Vector4(bindings.strength("thrust_forward") - bindings.strength("thrust_reverse"),
		bindings.strength("thrust_up") - bindings.strength("thrust_down"),
		bindings.strength("turn_left") - bindings.strength("turn_right"),
		bindings.strength("pitch_up") - bindings.strength("pitch_down"))
