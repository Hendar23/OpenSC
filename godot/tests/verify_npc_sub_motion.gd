extends SceneTree
const Motion = preload("res://npc_sub_motion.gd")
var checks := 0
var failures := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(text)
func simulate(rate: int) -> Dictionary:
	var motion := Motion.new(); var pose := Basis.IDENTITY; var point := Vector3.ZERO
	for tick in range(rate*8):
		var direction := Vector3.BACK if tick < rate*3 else Vector3.RIGHT
		pose = motion.step(1.0/rate,direction,2.0,2.0,pose); point += motion.velocity/rate
	return {"position":point,"basis":pose,"velocity":motion.velocity}
func _initialize() -> void:
	var motion := Motion.new(); var pose := Basis.IDENTITY
	pose = motion.step(1.0/60.0,Vector3.BACK,2.0,2.0,pose)
	check(motion.velocity.length() > 0 and motion.velocity.length() < 0.1,"NPC thrust accelerates gradually from rest")
	for tick in range(180): pose = motion.step(1.0/60.0,Vector3.BACK,2.0,2.0,pose)
	var before := motion.velocity
	pose = motion.step(1.0/60.0,Vector3.ZERO,0,2.0,pose)
	check(motion.velocity.length() > before.length()*0.9,"Releasing navigation thrust retains coasting momentum")
	pose = motion.step(1.0/60.0,Vector3.FORWARD,2.0,2.0,pose)
	check(motion.velocity.z > 0 and pose.z.z > 0.9,"Reversing the destination cannot instantly reverse velocity or hull heading")
	var leaned := false
	for tick in range(120):
		pose = motion.step(1.0/60.0,Vector3.RIGHT,2.0,2.0,pose)
		leaned = leaned or absf(pose.x.y) > 0.01
	check(leaned and absf(motion.bank) <= 0.14,"Moving turns bank subtly within an eight-degree limit")
	for tick in range(240): pose = motion.step(1.0/60.0,Vector3.ZERO,0,2.0,pose)
	check(motion.velocity.is_zero_approx() and absf(motion.bank) < 0.001,"Coasting settles without perpetual drift and returns upright")
	var low := simulate(30); var high := simulate(120)
	check(low.position.distance_to(high.position) < 0.15 and low.velocity.distance_to(high.velocity) < 0.01,"NPC flow is consistent across frame rates")
	print("NPC sub motion: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
