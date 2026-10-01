extends SceneTree
const Pilot = preload("res://submarine_controller.gd")
const Paths = preload("res://asset_paths.gd")
const Mods = preload("res://mod_registry.gd")
class FakeJoyInput extends RefCounted:
	var pads := [3, 7]
	var calls: Array[Dictionary] = []
	var stops: Array[int] = []
	func get_connected_joypads() -> Array: return pads
	func start_joy_vibration(device: int, weak: float, strong: float, duration: float) -> void:
		calls.append({"device": device, "weak": weak, "strong": strong, "duration": duration})
	func stop_joy_vibration(device: int) -> void: stops.append(device)
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(description)
func _run() -> void:
	Mods.initialize(false)
	var pilot := Pilot.new()
	pilot.remember_settings = false
	pilot.controls_enabled = false
	pilot.active = true
	root.add_child(pilot)
	pilot.visual = Node3D.new()
	pilot.add_child(pilot.visual)
	pilot.set_process(false)
	pilot.submarine_audio.setup(pilot, Paths.find_game_folder())
	var audio: Node = pilot.submarine_audio
	var rumble: Node = pilot.impact_rumble
	var joy := FakeJoyInput.new()
	rumble.joy_input = joy
	check(not audio.impact(0.1) and joy.calls.is_empty(), "Tiny contacts produce no rumble")
	audio.impact(0.6)
	check(joy.calls.size() == 1 and joy.calls[0].device == 3, "Accepted impact rumbles only the controller used for piloting")
	check(not audio.impact(3.0) and joy.calls.size() == 1, "Impact cooldown also prevents rumble chatter")
	var light: Dictionary = joy.calls[0]
	audio.update(0.4)
	audio.tuning.settings.master_volume = -60.0
	audio.impact(float(pilot.movement.settings.forward_speed))
	check(joy.calls.size() == 2, "Muting sound does not mute physical feedback")
	var hard: Dictionary = joy.calls[1]
	check(hard.weak > light.weak and hard.strong > light.strong and hard.duration > light.duration, "Hard impacts have stronger and longer rumble")
	check(hard.weak <= 1.0 and hard.strong <= 1.0 and hard.duration <= 0.220001 and light.duration > 0.0, "Motor strengths are bounded and duration is always finite")
	pilot.reset_at(Vector3.ZERO)
	check(joy.stops.back() == 3 and rumble.device == -1, "Reset stops an active impact pulse")
	audio.impact(3.0)
	rumble._process(0.3)
	check(rumble.device == -1, "Rumble stops after its short duration")
	audio.update(0.4)
	audio.impact(3.0)
	pilot.active = false
	check(rumble.device == -1, "Starting docking or disabling piloting stops rumble")
	pilot.active = true
	audio.update(0.4)
	audio.impact(3.0)
	rumble._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(rumble.device == -1, "Losing window focus stops rumble")
	audio.update(0.4)
	audio.impact(3.0)
	pilot.visual.hide()
	rumble._process(0.01)
	check(rumble.device == -1, "Hidden hull cancels physical feedback")
	pilot.visual.show()
	audio.update(0.4)
	var count := joy.calls.size()
	audio.tuning.settings.impact_rumble_strength = 0.0
	audio.impact(3.0)
	check(joy.calls.size() == count, "Zero rumble strength disables the effect")
	audio.update(0.4)
	audio.tuning.settings.impact_rumble_strength = 0.65
	joy.pads = []
	audio.impact(3.0)
	check(joy.calls.size() == count, "Keyboard play with no connected controller is harmless")
	joy.pads = [7]
	audio.update(0.4)
	audio.effect_players.impact_hit1.stream = null
	audio.effect_players.impact_hit3.stream = null
	audio.impact(3.0)
	check(joy.calls.back().device == 7, "Rumble follows the remaining controller and works even without sound files")
	joy.pads = []
	rumble.stop()
	check(rumble.device == -1, "Disconnecting a rumbling controller clears its state")
	pilot.free()
	await create_timer(0.25).timeout
	print("Impact rumble verification: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
