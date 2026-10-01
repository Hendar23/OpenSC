extends Node

var pilot: RigidBody3D
var joy_input: Object = Input
var device := -1
var remaining := 0.0

func impact(speed: float) -> void:
	if not is_instance_valid(pilot) or not pilot.active: return
	var strength := float(pilot.submarine_audio.tuning.settings.impact_rumble_strength)
	var pads: Array = joy_input.get_connected_joypads()
	if strength <= 0.0 or pads.is_empty(): return
	var severity := clampf(speed / maxf(0.1, float(pilot.movement.settings.forward_speed)), 0.0, 1.0)
	var pad := int(pads[0]) # Same controller used by pilot_input.gd.
	if device >= 0 and device != pad: stop()
	device = pad
	remaining = lerpf(0.08, 0.22, severity)
	joy_input.start_joy_vibration(device, strength * lerpf(0.2, 0.7, severity), strength * lerpf(0.15, 1.0, severity), remaining)

func _process(delta: float) -> void:
	if device < 0: return
	remaining -= delta
	if remaining <= 0.0 or not is_instance_valid(pilot) or not pilot.active or not is_instance_valid(pilot.visual) or not pilot.visual.is_visible_in_tree():
		stop()
	elif float(pilot.submarine_audio.tuning.settings.impact_rumble_strength) <= 0.0: stop()

func stop() -> void:
	if device >= 0 and device in joy_input.get_connected_joypads(): joy_input.stop_joy_vibration(device)
	device = -1
	remaining = 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT: stop()

func _exit_tree() -> void: stop()
