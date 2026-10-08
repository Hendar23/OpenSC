extends SceneTree
const Pilot = preload("res://submarine_controller.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var pilot := Pilot.new(); pilot.remember_settings = false; pilot.active = true; root.add_child(pilot)
	pilot.visual = Node3D.new(); pilot.add_child(pilot.visual)
	pilot.movement.settings.impact_damage_threshold = 0.75; pilot.movement.settings.impact_damage_scale = 1.0
	pilot.apply_impact_damage(0.5)
	check(pilot.health == 100,"Gentle contact causes no damage")
	pilot.apply_impact_damage(2.0)
	check(pilot.health < 100,"Harder impact damages shields")
	var low_loss: float = 100 - pilot.health
	pilot.restore_health(); pilot.apply_impact_damage(4.0)
	check(100 - pilot.health > low_loss,"Faster impact causes more damage")
	pilot.restore_health(); pilot.controls_enabled = false; pilot.apply_impact_damage(10)
	check(pilot.health == 100,"Docking and disabled controls protect shields")
	pilot.controls_enabled = true; pilot.movement.settings.impact_damage_scale = 0; pilot.apply_impact_damage(10)
	check(pilot.health == 100,"Zero multiplier disables impact damage")
	pilot.movement.settings.impact_damage_scale = 1
	var wall := StaticBody3D.new(); wall.position = Vector3(2,0,0)
	var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(0.5,10,10); shape.shape = box; wall.add_child(shape); root.add_child(wall)
	pilot.reset_at(Vector3.ZERO); pilot.velocity = Vector3.RIGHT * 4
	for frame in range(90): await physics_frame
	check(pilot.health < 100 and pilot.health > 50,"A real wall collision damages the hull without destroying it")
	var after_hit: float = pilot.health
	for frame in range(60):
		pilot.velocity = Vector3.RIGHT * 0.1; await physics_frame
	check(is_equal_approx(pilot.health,after_hit),"Remaining against a wall does not repeatedly drain shields")
	wall.free(); pilot.restore_health(); pilot.reset_at(Vector3.ZERO)
	var water := StaticBody3D.new(); water.collision_layer = 4; water.collision_mask = 2; water.position = Vector3(0,1.5,0)
	var water_shape := CollisionShape3D.new(); var water_box := BoxShape3D.new(); water_box.size = Vector3(10,0.5,10); water_shape.shape = water_box; water.add_child(water_shape); root.add_child(water)
	pilot.velocity = Vector3.UP * 3
	for frame in range(60): await physics_frame
	check(pilot.health == 100,"The water surface causes no collision damage")
	water.free(); pilot.restore_health(); pilot.reset_at(Vector3.ZERO)
	var fish := preload("res://fish_controller.gd").new()
	fish.setup(Node3D.new(),Vector3(2,0,0),AABB(Vector3.ONE * -100,Vector3.ONE * 200),100,0.06,42)
	root.add_child(fish); fish.swim_speed = 0
	pilot.velocity = Vector3.RIGHT * 4
	for frame in range(90): await physics_frame
	check(pilot.health == 100 and fish.health == fish.max_health,"Real submarine/wildlife contacts cause no damage to either body")
	check(fish.position.x > 2.1,"Submarine contact pushes the creature aside")
	fish.free()
	pilot.apply_impact_damage(100)
	check(pilot.dead,"Fatal impact uses submarine destruction")
	pilot.free()
	print("Impact damage: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
