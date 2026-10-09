extends SceneTree
const Fish = preload("res://fish_controller.gd")
const Population = preload("res://wildlife_population.gd")
const Document = preload("res://map_document.gd")
var checks := 0
var failures := 0
var world: Node3D
var population: Node3D
class PlayerTarget extends CharacterBody3D:
	var health := 100.0
	var dead := false
	var active := true
	var controls_enabled := true
	var radius := 0.2
	func take_damage(amount: float, _source: Vector3 = Vector3.ZERO) -> void: health -= amount
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func creature(point: Vector3, role: String, size: float = 0.2) -> CharacterBody3D:
	var fish := Fish.new()
	fish.setup(Node3D.new(),point,AABB(Vector3(-100,-100,-100),Vector3.ONE * 200),100,size,42)
	fish.configure_combat({"food_role":role,"has_zapper":false})
	fish.population = population; fish.response = "ignore"; fish.swim_speed = 0
	population.add_child(fish)
	return fish
func _initialize() -> void: call_deferred("run")
func run() -> void:
	world = Node3D.new(); root.add_child(world)
	population = Population.new(); population.world = world; world.add_child(population)
	var folder := ProjectSettings.globalize_path("res://../Original Sub Culture")
	for index in range(1,4):
		population.zapper_frames.append(preload("res://clump_loader.gd")._load_texture(folder,"ZAPPER%d" % index,"ZAPPER%dM" % index,{}))
	var camera := Camera3D.new(); world.add_child(camera); camera.position = Vector3(2,1,2); camera.look_at(Vector3(0,0,-1)); camera.current = true
	var predator := creature(Vector3.ZERO,"predator")
	var prey := creature(Vector3(0,0,-0.45),"prey")
	var neutral := creature(Vector3(0,0,-0.3),"neutral")
	await physics_frame
	predator.combat.scan_timer = 0; predator.combat.perceive(0.01)
	check(predator.combat.target == prey,"Predators select prey and ignore closer neutral creatures")
	prey.combat.scan_timer = 0; prey.combat.perceive(0.01)
	check(prey.combat.threat == predator,"Prey detects predators using its detection distance")
	neutral.combat.scan_timer = 0; neutral.combat.perceive(0.01)
	check(neutral.combat.target == null and neutral.combat.threat == null,"Neutral wildlife ignores predators")
	check(prey.flee_range == 4.0 and predator.attack_range == 8.0,"Legacy detection becomes half-distance fleeing and unchanged attack detection")
	prey.position.z = -6; population.cells_frame = -1
	predator.combat.scan_timer = 0; predator.combat.perceive(0.01)
	prey.combat.scan_timer = 0; prey.combat.perceive(0.01)
	check(predator.combat.target == prey and prey.combat.threat == null,"Predator can detect prey beyond the prey's shorter flee range")
	prey.flee_range = 7; predator.attack_range = 3
	prey.combat.scan_timer = 0; prey.combat.perceive(0.01)
	predator.combat.scan_timer = 0; predator.combat.perceive(0.01)
	check(prey.combat.threat == predator and predator.combat.target == null,"Flee and attack detection ranges are independently adjustable")
	prey.flee_range = 4; predator.attack_range = 8; prey.position.z = -0.45; population.cells_frame = -1
	predator.combat.scan_timer = 0; predator.combat.perceive(0.01)
	predator.direction = Vector3.FORWARD; predator.combat.bite_timer = 0
	var before: float = prey.health
	predator.combat.attack(0.1)
	check(is_equal_approx(before - prey.health,5.0),"Unarmed predators bite at close range")
	predator.combat.attack(0.1)
	check(is_equal_approx(before - prey.health,5.0),"Bite interval prevents damage every frame")
	prey.health = 100; predator.combat.settings.has_zapper = true
	prey.position.z = -2; await physics_frame
	predator.combat.target = prey; predator.direction = Vector3.FORWARD
	before = prey.health; predator.combat.attack(0.1)
	check(is_equal_approx(before - prey.health,1.0),"Armed predators use continuous zapper damage at range")
	check(predator.combat.weapon.firing,"Creature weapon uses the original zapper animation")
	if DisplayServer.get_name() != "headless":
		await process_frame; await RenderingServer.frame_post_draw
		var ribbon: ArrayMesh = predator.combat.weapon.beam.mesh
		check(ribbon.get_surface_count() == 1,"Creature zapper renders a crackling ribbon")
		root.get_texture().get_image().save_png("res://tests/creature-zapper-preview.png")
	var wall := StaticBody3D.new(); wall.collision_layer = 1
	var collider := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = Vector3(2,2,0.1); collider.shape = shape
	wall.add_child(collider); world.add_child(wall); wall.position.z = -1
	await physics_frame
	before = prey.health; predator.combat.attack(0.1)
	check(prey.health == before,"Terrain blocks creature zapper damage")
	wall.free()
	prey.position.z = -20; population.cells_frame = -1
	prey.combat.scan_timer = 0; prey.combat.perceive(0.01)
	check(prey.combat.threat == null,"Prey stops reacting beyond its detection distance")
	prey.position.z = -2; prey.set_meta("wildlife_awake",false); population.cells_frame = -1
	predator.combat.scan_timer = 0; predator.combat.perceive(0.01)
	check(predator.combat.target == null,"Dormant wildlife cannot be hunted")
	var player := PlayerTarget.new(); player.collision_layer = 2; player.collision_mask = 0
	var player_shape := CollisionShape3D.new(); var player_ball := SphereShape3D.new(); player_ball.radius = player.radius; player_shape.shape = player_ball
	player.add_child(player_shape); world.add_child(player); player.set_physics_process(true); player.position.z = -2
	population.player = player; neutral.position.x = 40; prey.position.x = 30
	await physics_frame
	predator.response = "ignore"; predator.combat.target = null; predator._physics_process(0.1)
	check(player.health == 100,"Predator role alone does not make wildlife attack the submarine")
	predator.response = "attack"; predator.direction = Vector3.FORWARD; predator._physics_process(0.1)
	check(player.health < 100,"Existing attack response enables weapon damage against the submarine")
	player.health = 100; predator.response = "defend"; predator.defense_timer = 0; predator.combat.target = null; predator._physics_process(0.1)
	check(player.health == 100,"Defend response leaves the submarine alone until provoked")
	predator.take_damage(1); predator.direction = Vector3.FORWARD; predator._physics_process(0.1)
	check(player.health < 100,"Provoked defenders retaliate using their weapon")
	player.controls_enabled = false; player.health = 100; predator._physics_process(0.1)
	check(player.health == 100,"Docking or disabled submarine controls stop creature attacks")
	population.player = null; player.free()
	prey.set_meta("wildlife_awake",true)
	check(predator.collision_mask & 2 != 0 and predator.collision_layer == 8,"Wildlife colliders include the submarine")
	var small := creature(Vector3(20,0,0),"neutral",0.1)
	var large := creature(Vector3(25,0,0),"neutral",2.0)
	small.receive_sub_push(Vector3.RIGHT * 3,0.5); large.receive_sub_push(Vector3.RIGHT * 3,0.5)
	check(small.pushed_velocity.length() > large.pushed_velocity.length() * 5,"Model-sized bodies determine how readily wildlife yields to the sub")
	check(small.health == small.max_health and large.health == large.max_health,"Pushing wildlife does not damage it")
	check(Document.creature_combat({"model":"PIRANHA"}).food_role == "predator" and not Document.creature_combat({"model":"PIRANHA"}).has_zapper,"Piranhas default to predators with bites")
	check(Document.creature_combat({"model":"MJACK"}).has_zapper and Document.creature_combat({"model":"TURTLE"}).food_role == "neutral","Mutant defaults to zapper and turtles to neutral")
	var map := Document.load_active()
	map.species[0].attack_interval = 0
	check(not Document.valid(map),"Invalid combat timing is rejected for maps and mods")
	population.set_simulating(false)
	check(predator.combat.weapon == null or not predator.combat.weapon.firing,"Pausing wildlife stops weapon effects")
	world.free()
	print("Wildlife combat: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
