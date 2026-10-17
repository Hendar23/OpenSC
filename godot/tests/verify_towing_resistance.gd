extends SceneTree
const Movement = preload("res://movement_model.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func cruise(load: float, throttle: float = 1.0) -> float:
	var model := Movement.new()
	var config := ConfigFile.new(); config.load("res://submarine_tuning.cfg"); Movement._apply_values(config,model.settings)
	model.cargo_mass = load
	for tick in range(7200): model.step(1.0/120.0,Basis.IDENTITY,throttle,0,0)
	return absf(model.velocity.z)
func _initialize() -> void:
	var empty := cruise(0); var light := cruise(40); var heavy := cruise(250)
	print("Cruising speed: unloaded %.3f, shuttle at multiplier4 %.3f, shuttle at multiplier25 %.3f" % [empty,light,heavy])
	check(light < empty * 0.85,"A modest weighted shuttle load reduces sustained cruising speed")
	check(heavy < light * 0.65,"Increasing cargo multiplier produces stronger towing resistance")
	check(cruise(250,-1) < cruise(0,-1),"Towing resistance also reduces reverse cruising speed")
	var model := Movement.new(); model.cargo_mass = 250
	for tick in range(1800): model.step(1.0/60.0,Basis.IDENTITY,1,0,0)
	model.cargo_mass = 0
	for tick in range(1800): model.step(1.0/60.0,Basis.IDENTITY,1,0,0)
	check(is_equal_approx(absf(model.velocity.z),float(model.settings.forward_speed)),"Releasing cargo restores unloaded speed without changing settings")
	print("Towing resistance: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
