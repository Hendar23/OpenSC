extends SceneTree
const Damage = preload("res://original_damage.gd")
const Pilot = preload("res://submarine_controller.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	check(is_equal_approx(Damage.terrain(4,100),0.56),"Terrain raw shields, ticks and reference mass convert to displayed points")
	check(is_equal_approx(Damage.terrain(8,100),Damage.terrain(4,100)*2),"Terrain damage scales linearly with speed")
	check(is_equal_approx(Damage.terrain(4,200),Damage.terrain(4,100)*0.5),"Original terrain formula divides by mass")
	check(is_equal_approx(Damage.object_contact(4,0.1),0.56),"Object damage uses closing speed and inflict")
	check(Damage.object_contact(4,0.0006) < Damage.object_contact(4,0.1),"Thorium contact uses its original smaller inflict")
	check(is_equal_approx(Damage.radiation(5,0.5),10) and is_equal_approx(Damage.radiation(5,2),2.5),"Radiation follows inverse distance")
	check(is_finite(Damage.radiation(5,0)),"Coincident radiation source remains finite")
	check(is_equal_approx(Damage.radiation_strength(0.0006),0.0525),"Original radiation clock maps seconds to 25 engine steps")
	var pilot := Pilot.new(); pilot.remember_settings = false; root.add_child(pilot); pilot.active = true; pilot.freeze = true
	pilot.movement.settings.impact_damage_threshold = 0; pilot.movement.settings.impact_damage_scale = 1
	pilot.restore_health(100,4); pilot.apply_impact_damage(10)
	check(pilot.health == 4,"Terrain pre-hit gate protects shields at four percent")
	pilot.restore_health(100,4.1); pilot.apply_impact_damage(10)
	check(pilot.health < 4,"Terrain damage can cross below four percent")
	pilot.restore_health(100,4); pilot.apply_impact_damage(10,0.1)
	check(pilot.health < 4,"Object contacts do not use the terrain shield gate")
	pilot.restore_health(); pilot.hull_rating = 120; pilot.take_damage(35)
	check(is_equal_approx(pilot.health,75),"First hull upgrade reduces a baseline 35 hit to 25")
	pilot.restore_health(); pilot.hull_rating = 200; pilot.take_damage(35)
	check(is_equal_approx(pilot.health,95) and pilot.max_health == 100,"Maximum hull protection reduces damage without increasing shields")
	pilot.restore_health(); pilot.hull_rating = 100; pilot.radiation_rating = 100; pilot.receive_radiation(10,1)
	check(is_equal_approx(pilot.health,98) and pilot.radiation_exposed,"Maximum radiation upgrade leaves twenty percent radiation damage and warning")
	pilot.restore_health(); pilot.hull_rating = 120; pilot.receive_radiation(14,1)
	check(is_equal_approx(pilot.health,98),"Hull and radiation protection combine")
	pilot.restore_health(); pilot.hull_rating = 100
	Damage.weapon(pilot,2.5,Vector3.ZERO)
	check(is_equal_approx(pilot.health,91.25),"Raw weapon strength converts to shield points and applies base hull once")
	pilot.restore_health(); pilot.hull_rating = 120
	Damage.weapon(pilot,2.5,Vector3.ZERO)
	check(is_equal_approx(pilot.health,93.75),"Upgraded hull applies exactly once to raw weapon damage")
	var fish := preload("res://fish_controller.gd").new()
	fish.damage_sustain = 0.25; fish.configure_health(10)
	Damage.weapon(fish,2.5,Vector3.ZERO)
	check(is_equal_approx(fish.health,9.375),"Creature health stays raw and uses its own original sustain")
	fish.free()
	check(Pilot.VISUAL_SCALE == 1.0,"Submarine preserves imported original size")
	pilot.free()
	print("Original damage: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
