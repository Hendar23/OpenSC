extends "res://tests/test_scene_tree.gd"
const Jobs = preload("res://stage_two_missions.gd")
class Victim extends CharacterBody3D:
	var dead := false
class Traffic extends Node3D:
	var explosion_frames: Array[Texture2D] = []
	var explosion_sound: AudioStream
class Context extends Node3D:
	var pilot: Node3D
	var world_root: Node3D
	var submarine_traffic: Node3D
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	preload("res://player_storage.gd").root_override = "res://tests/cache-covert-defence-fixtures"
	call_deferred("run")
func run() -> void:
	var game := Context.new(); root.add_child(game); game.world_root = game
	game.pilot = Victim.new(); game.add_child(game.pilot); game.pilot.position = Vector3(0,0,5)
	game.submarine_traffic = Traffic.new(); game.add_child(game.submarine_traffic)
	var jobs := Jobs.new(); game.add_child(jobs); jobs.game = game; jobs.set_physics_process(false)
	jobs.missile_template = preload("res://clump_loader.gd").load_clump(ProjectSettings.globalize_path("res://../Original Sub Culture/CLUMPS/TMISSILE.DFF"))
	check(jobs.missile_template != null,"Original TECHOUTPOST TMISSILE model loads")
	if jobs.missile_template == null: game.free(); quit(1); return
	jobs.add_child(jobs.missile_template); jobs.missile_template.hide()
	var building := Node3D.new(); game.add_child(building)
	var vent := preload("res://mission_vent.gd").new(); game.add_child(vent); vent.position = Vector3(20,0,0)
	var shell := StaticBody3D.new(); building.add_child(shell)
	var collision := CollisionShape3D.new(); collision.shape = BoxShape3D.new(); collision.shape.size = Vector3(4,4,4); shell.add_child(collision); vent.shell = shell
	var defence := {"model":building,"vent":vent,"clock":0.0}
	await physics_frame; await physics_frame
	var missile := jobs._fire_base(defence)
	check(missile != null,"Building can fire with its own collision shell excluded")
	if missile == null: game.free(); quit(1); return
	check(missile.global_position.is_equal_approx(Vector3(0,0,1)) and missile.global_position.distance_to(vent.global_position) > 10,"Missile starts one aimed unit from the building, independently of the remote vent")
	check(not missile.homing and missile.source_exclusions == [shell.get_rid()],"Unguided base missile ignores only its own building shell")
	missile.set_physics_process(false); missile._physics_process(0.04)
	check(not missile.is_queued_for_deletion() and missile.global_position.z > 1.0,"A missile can leave its building without immediately exploding on its own wall")
	var wall := StaticBody3D.new(); game.add_child(wall); wall.position.z = 2.5
	var wall_collision := CollisionShape3D.new(); wall_collision.shape = BoxShape3D.new(); wall_collision.shape.size = Vector3(4,4,0.1); wall.add_child(wall_collision)
	await physics_frame; await physics_frame
	for frame in range(40):
		if missile.is_queued_for_deletion(): break
		missile._physics_process(0.04)
	check(missile.is_queued_for_deletion(),"Base missile still hits other scenery after excluding its own shell")
	await process_frame
	check(jobs._fire_base(defence) == null,"An intervening wall blocks a new building shot")
	wall.free(); await physics_frame; await physics_frame
	game.pilot.position = Vector3(0,0,11)
	check(jobs._fire_base(defence) == null,"Base does not fire at the original eleven-unit range boundary")
	game.pilot.position = Vector3(0,0,5); game.pilot.velocity = Vector3.RIGHT
	var leading := jobs._fire_base(defence)
	check(leading != null and leading.direction.x > 0,"Building aim leads a moving player through the original shared interception helper")
	if leading != null: leading.queue_free()
	game.pilot.velocity = Vector3.ZERO
	vent.dead = true
	check(jobs._fire_base(defence) == null,"Destroying the internal target disables its associated building weapon")
	vent.dead = false; vent.open = false
	jobs.base_defences = [defence,{"model":building,"vent":vent,"clock":9.0}]
	var before := jobs.actors.size()
	jobs._step_base_defences(0.04)
	check(jobs.actors.size() == before+1,"A closed vent does not prevent the building's independently due shot")
	check(float(defence.clock) >= 64.0/25.0 and float(defence.clock) <= 127.0/25.0,"Original reload resets to 64..127 ticks")
	check(is_equal_approx(float(jobs.base_defences[1].clock),8.96),"Other buildings keep their independent cooldown instead of firing in a shared volley")
	before = jobs.actors.size(); vent.dead = true; jobs._step_base_defences(100)
	check(jobs.actors.size() == before,"Disabled buildings cannot resume firing when their cooldown expires")
	jobs.missile_template = null; game.free()
	print("Covert building defences: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
