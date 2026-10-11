extends Node

var pilot: RigidBody3D
var joy_input: Object = Input
var device := -1
var remaining := 0.0
var strong_pulse := false
var survives_destruction := false

func impact(speed: float) -> void:
	if strong_pulse: return
	if not is_finite(speed) or speed <= 0 or not is_instance_valid(pilot) or not pilot.active: return
	var strength := float(pilot.submarine_audio.tuning.settings.impact_rumble_strength)
	var pads: Array = joy_input.get_connected_joypads()
	if strength <= 0.0 or pads.is_empty(): return
	var severity := clampf(speed / maxf(0.1, float(pilot.movement.settings.forward_speed)), 0.0, 1.0)
	var pad := int(pads[0]) # Same controller used by pilot_input.gd.
	if device >= 0 and device != pad: stop()
	device = pad
	remaining = lerpf(0.16, 0.35, severity)
	joy_input.start_joy_vibration(device, strength * lerpf(0.55, 1.0, severity), strength * lerpf(0.5, 1.0, severity), remaining)

func damage(amount: float, hull_strength: float = 100.0) -> void:
	if strong_pulse: return
	if amount <= 0.0 or not is_instance_valid(pilot) or not pilot.active: return
	var strength := float(pilot.submarine_audio.tuning.settings.impact_rumble_strength)
	var pads: Array = joy_input.get_connected_joypads()
	if strength <= 0.0 or pads.is_empty(): return
	var severity := clampf(amount / maxf(1.0,hull_strength),0.0,1.0)
	var pad := int(pads[0])
	if device >= 0 and device != pad: stop()
	device = pad; remaining = lerpf(0.12,0.45,severity)
	joy_input.start_joy_vibration(device,strength * lerpf(0.3,0.8,severity),strength * lerpf(0.4,1.0,severity),remaining)

func explosion() -> void:
	if not is_instance_valid(pilot) or not pilot.active: return
	_blast_pulse(0.65,false)

func destruction() -> void:
	_blast_pulse(1.2,true)

func _blast_pulse(duration: float, terminal: bool) -> void:
	if not is_instance_valid(pilot): return
	var strength := clampf(float(pilot.submarine_audio.tuning.settings.impact_rumble_strength),0.0,1.0)
	var pads: Array = joy_input.get_connected_joypads()
	if strength <= 0.0 or pads.is_empty(): return
	var pad := int(pads[0])
	if device >= 0 and device != pad: stop()
	device = pad; remaining = duration; strong_pulse = true; survives_destruction = terminal
	joy_input.start_joy_vibration(device,strength,strength,remaining)

func _process(delta: float) -> void:
	if device < 0: return
	remaining -= delta
	if remaining <= 0.0 or not is_instance_valid(pilot):
		stop()
	elif not survives_destruction and (not pilot.active or not is_instance_valid(pilot.visual) or not pilot.visual.is_visible_in_tree()): stop()
	elif float(pilot.submarine_audio.tuning.settings.impact_rumble_strength) <= 0.0: stop()

func stop() -> void:
	if device >= 0 and device in joy_input.get_connected_joypads(): joy_input.stop_joy_vibration(device)
	device = -1
	remaining = 0.0
	strong_pulse = false; survives_destruction = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT: stop()

func _exit_tree() -> void: stop()
