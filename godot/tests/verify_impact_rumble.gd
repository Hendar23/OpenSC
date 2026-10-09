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
	rumble.impact(0.1)
	check(joy.calls.size() == 1, "Tiny contacts produce rumble even below sound and damage thresholds")
	rumble.impact(0.6)
	check(joy.calls.size() == 2 and joy.calls[0].device == 3, "Impact rumbles only the controller used for piloting")
	audio.impact_cooldown = 10; rumble.impact(3.0)
	check(joy.calls.size() == 3, "Sound cooldown does not suppress impact rumble")
	var light: Dictionary = joy.calls[1]
	audio.update(0.4)
	audio.tuning.settings.master_volume = -60.0
	rumble.impact(float(pilot.movement.settings.forward_speed))
	check(joy.calls.size() == 4, "Muting sound does not mute physical feedback")
	var hard: Dictionary = joy.calls[3]
	check(hard.weak > light.weak and hard.strong > light.strong and hard.duration > light.duration, "Hard impacts have stronger and longer rumble")
	check(hard.weak <= 1.0 and hard.strong <= 1.0 and hard.duration <= 0.350001 and light.duration >= 0.16 and light.strong >= 0.3, "Impact pulses are stronger and longer, with bounded motor strengths")
	pilot.reset_at(Vector3.ZERO)
	check(joy.stops.back() == 3 and rumble.device == -1, "Reset stops an active impact pulse")
	rumble.impact(3.0)
	rumble._process(0.4)
	check(rumble.device == -1, "Rumble stops after its short duration")
	audio.update(0.4)
	rumble.impact(3.0)
	pilot.active = false
	check(rumble.device == -1, "Starting docking or disabling piloting stops rumble")
	pilot.active = true
	audio.update(0.4)
	rumble.impact(3.0)
	rumble._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(rumble.device == -1, "Losing window focus stops rumble")
	audio.update(0.4)
	rumble.impact(3.0)
	pilot.visual.hide()
	rumble._process(0.01)
	check(rumble.device == -1, "Hidden hull cancels physical feedback")
	pilot.visual.show()
	audio.update(0.4)
	var count := joy.calls.size()
	audio.tuning.settings.impact_rumble_strength = 0.0
	rumble.impact(3.0)
	check(joy.calls.size() == count, "Zero rumble strength disables the effect")
	audio.update(0.4)
	audio.tuning.settings.impact_rumble_strength = 0.65
	joy.pads = []
	rumble.impact(3.0)
	check(joy.calls.size() == count, "Keyboard play with no connected controller is harmless")
	joy.pads = [7]
	audio.update(0.4)
	audio.effect_players.impact_hit1.stream = null
	audio.effect_players.impact_hit3.stream = null
	rumble.impact(3.0)
	check(joy.calls.back().device == 7, "Rumble follows the remaining controller and works even without sound files")
	var before_damage := joy.calls.size()
	pilot.controls_enabled = true
	pilot.receive_radiation(5,1)
	check(pilot.health == 95 and joy.calls.size() == before_damage,"Radiation damages shields without controller rumble")
	rumble.damage(30.0)
	var damage_light: Dictionary = joy.calls.back()
	rumble.damage(60.0)
	var damage_hard: Dictionary = joy.calls.back()
	check(joy.calls.size() == before_damage + 2 and damage_light.device == 7, "Damage rumbles the piloting controller")
	check(damage_hard.strong > damage_light.strong and damage_hard.duration > damage_light.duration, "Greater damage produces stronger and longer rumble")
	before_damage = joy.calls.size()
	rumble.damage(0.0)
	check(joy.calls.size() == before_damage, "Zero damage does not rumble")
	audio.tuning.settings.impact_rumble_strength = 0.0
	rumble.damage(30.0)
	check(joy.calls.size() == before_damage, "Damage respects the rumble strength setting")
	audio.tuning.settings.impact_rumble_strength = 0.65
	joy.pads = []
	rumble.damage(30.0)
	check(joy.calls.size() == before_damage, "Damage is harmless with no controller")
	rumble.stop()
	check(rumble.device == -1, "Disconnecting a rumbling controller clears its state")
	pilot.free()
	await create_timer(0.25).timeout
	print("Impact rumble verification: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
