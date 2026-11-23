extends SceneTree
const Fish = preload("res://fish_controller.gd")
const Population = preload("res://wildlife_population.gd")
const Document = preload("res://map_document.gd")
var checks := 0
var failures := 0
var world: Node3D
var population: Node3D
class FixtureFish extends Fish:
	# Run gameplay steps explicitly so renderer timing cannot consume a burst.
	func _physics_process(_delta: float) -> void: pass
	func step(delta: float) -> void: super._physics_process(delta)

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
func creature(point: Vector3, role: String, size: float = 0.2) -> FixtureFish:
	var fish := FixtureFish.new()
	fish.setup(Node3D.new(),point,AABB(Vector3(-100,-100,-100),Vector3.ONE * 200),100,size,42)
	fish.configure_combat({"food_role":role,"has_zapper":false})
	fish.population = population; fish.response = "ignore"; fish.swim_speed = 0
	population.add_child(fish)
	return fish
func _initialize() -> void: call_deferred("run")
func run() -> void:
	world = Node3D.new(); root.add_child(world)
	population = Population.new(); population.world = world; world.add_child(population)
	preload("res://player_storage.gd").root_override = "user://wildlife-combat-fixture"
	DirAccess.make_dir_recursive_absolute("user://wildlife-combat-fixture/Mods")
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../Original Sub Culture")
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
	neutral.position.x = 40
	prey.health = 100; predator.combat.settings.has_zapper = true
	predator.combat.settings["zapper_chance"] = 0
	prey.position.z = -1.2; await physics_frame
	predator.combat.target = prey; predator.direction = Vector3.FORWARD
	predator.combat.zap_ticks_left = 3
	before = prey.health; predator.combat.attack(0.04)
	check(is_equal_approx(before - prey.health,0.1),"Armed predators use raw burst-tick damage")
	check(predator.combat.weapon.firing,"Creature weapon uses the original zapper animation")
	if DisplayServer.get_name() != "headless":
		await process_frame; await RenderingServer.frame_post_draw
		var ribbon: ArrayMesh = predator.combat.weapon.beam.mesh
		check(ribbon.get_surface_count() == 1,"Creature zapper renders a crackling ribbon")
		root.get_texture().get_image().save_png("user://wildlife-combat-fixture/creature-zapper-preview.png")
	before = prey.health
	predator.combat.attack(0.08)
	check(is_equal_approx(before - prey.health,0.2) and predator.combat.zap_ticks_left == 0 and not predator.combat.weapon.firing,"Mutant burst ends after three original updates")
	predator.combat.attack(0.0)
	check(not predator.combat.weapon.firing,"Idle visual updates cannot restart a Mutant burst")
	# A visible target inside the old 49-degree cone must not bend the beam.
	before = prey.health
	predator.direction = (prey.global_position - predator.global_position).normalized().rotated(Vector3.UP,deg_to_rad(20))
	predator.combat.attack(0.1)
	check(prey.health == before and not predator.combat.weapon.firing,"Zapper cannot aim sideways within the old attack cone")
	predator.direction = -(prey.global_position - predator.global_position).normalized()
	predator.combat.attack(0.1)
	check(prey.health == before,"Zapper cannot fire behind the fish")
	predator.direction = (prey.global_position - predator.global_position).normalized().rotated(Vector3.RIGHT,deg_to_rad(20))
	predator.combat.attack(0.1)
	check(prey.health == before,"Zapper cannot bend upwards or downwards to a target")
	predator.direction = Vector3.RIGHT
	var aim := (prey.global_position - predator.global_position).normalized()
	predator._steer(aim,0.1); predator._update_orientation(); predator.combat.attack(0.1)
	check(prey.health == before,"Fish cannot instantly turn and fire at a sideways target")
	for step in range(40): predator._steer(aim,0.1)
	predator.combat.zap_ticks_left = 3
	predator._update_orientation(); predator.combat.attack(0.1)
	check(prey.health < before,"Fish can zap after steering its nose onto target")
	var beam_direction: Vector3 = (predator.combat.weapon.beam_end - predator.combat.weapon.beam_start).normalized()
	check(beam_direction.dot(predator.direction) > 0.99999,"Rendered zapper beam follows the fish heading")
	var wall := StaticBody3D.new(); wall.collision_layer = 1
	var collider := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = Vector3(2,2,0.1); collider.shape = shape
	wall.add_child(collider); world.add_child(wall); wall.position.z = -1
	await physics_frame
	predator.direction = (prey.global_position - predator.global_position).normalized()
	predator.combat.zap_ticks_left = 3; predator.combat.zap_clock = 0
	before = prey.health; predator.combat.attack(0.04)
	check(prey.health == before,"Terrain blocks creature zapper damage")
	check(predator.combat.weapon.firing and predator.combat.weapon.beam_end.z > prey.global_position.z,"The forward burst stops at intervening terrain")
	wall.free()
	prey.position.z = -20; population.cells_frame = -1
	prey.combat.scan_timer = 0; prey.combat.perceive(0.01)
	check(prey.combat.threat == null,"Prey stops reacting beyond its detection distance")
	prey.position.z = -1.2; prey.set_meta("wildlife_awake",false); population.cells_frame = -1
	predator.combat.scan_timer = 0; predator.combat.perceive(0.01)
	check(predator.combat.target == null,"Dormant wildlife cannot be hunted")
	var player := PlayerTarget.new(); player.collision_layer = 2; player.collision_mask = 0
	var player_shape := CollisionShape3D.new(); var player_ball := SphereShape3D.new(); player_ball.radius = player.radius; player_shape.shape = player_ball
	player.add_child(player_shape); world.add_child(player); player.set_physics_process(true); player.position.z = -1.2
	population.player = player; neutral.position.x = 40; prey.position.x = 30
	await physics_frame
	predator.response = "ignore"; predator.combat.target = null; predator.step(0.1)
	check(player.health == 100,"Predator role alone does not make wildlife attack the submarine")
	predator.combat.zap_ticks_left = 3; predator.response = "attack"; predator.avoidance_timer = 0; predator.direction = (player.global_position - predator.global_position).normalized(); predator.step(0.1)
	check(player.health < 100,"Existing attack response enables weapon damage against the submarine")
	# Reposition outside the proximity trigger after the earlier attack step.
	predator.response = "ignore"; predator.combat.target = null
	player.position = predator.global_position + Vector3.FORWARD * 1.2
	await physics_frame
	player.health = 100; predator.response = "defend"; predator.defense_timer = 0; predator.step(0.1)
	check(player.health == 100,"Defend response leaves the submarine alone until provoked")
	predator.combat.zap_ticks_left = 3; predator.take_damage(1); predator.avoidance_timer = 0; predator.direction = (player.global_position - predator.global_position).normalized(); predator.step(0.1)
	check(player.health < 100,"Provoked defenders retaliate using their weapon")
	player.controls_enabled = false; player.health = 100; predator.step(0.1)
	check(player.health == 100,"Docking or disabled submarine controls stop creature attacks")
	player.controls_enabled = true
	predator.response = "attack"; predator.avoidance_timer = 0
	predator.combat.settings["zapper_chance"] = 256
	player.position = predator.global_position + Vector3.FORWARD * 1.3 + Vector3.RIGHT * 0.3
	await physics_frame
	predator.direction = Vector3.FORWARD
	predator.combat.target = player; predator.combat.zap_ticks_left = 0; predator.combat.zap_clock = 0
	before = player.health; predator.combat.attack(0.04)
	check(predator.combat.zap_ticks_left == 2 and predator.combat.weapon.firing and player.health == before,"A lined-up fish can fire a forward burst that misses its target")
	check(predator.combat.weapon.beam_end.is_equal_approx(predator.global_position + Vector3.FORWARD * 1.8),"A missed burst draws to its full forward reach")
	predator.direction = Vector3.BACK
	predator.combat.zap_ticks_left = 0; predator.combat.zap_clock = 0
	predator.combat.attack(0.04)
	check(predator.combat.zap_ticks_left == 0 and not predator.combat.weapon.firing,"A target behind the fish cannot start a forward burst")
	player.position = predator.global_position + Vector3.FORWARD * 0.6
	await physics_frame
	predator.direction = Vector3.FORWARD; predator.combat.target = player
	predator.combat.zap_ticks_left = 0; predator.combat.zap_clock = 0
	before = player.health; predator.combat.attack(0.04)
	check(player.health < before and predator.combat.weapon.firing,"A zapper muzzle inside a nearby target still deals damage and shows an arc")
	# The target is now entirely between the fish and its usual muzzle.
	player.position = predator.global_position + Vector3.FORWARD * 0.25
	await physics_frame
	predator.combat.zap_ticks_left = 0; predator.combat.zap_clock = 0
	before = player.health; predator.combat.attack(0.04)
	check(is_equal_approx(before - player.health,0.1) and predator.combat.weapon.firing,"A point-blank target takes zapper damage and shows an arc")

	# The fish gets a 25 Hz firing update even if its alignment lasts just one
	# 60 Hz physics frame as it turns around the hull.
	predator.combat.zap_ticks_left = 0; predator.combat.zap_clock = 0
	predator.direction = Vector3.BACK
	predator.combat.attack(1.0 / 60.0)
	predator.combat.attack(1.0 / 60.0)
	predator.direction = Vector3.FORWARD
	before = player.health; predator.combat.attack(1.0 / 60.0)
	check(is_equal_approx(before - player.health,0.1),"A short opening uses the existing original tick phase")

	predator.combat.configure(predator,{"model":"MUTANT","has_zapper":true})
	predator.combat.settings["zapper_chance"] = 256
	player.position = predator.global_position + Vector3.FORWARD * 2.5
	await physics_frame
	predator.combat.target = player; predator.combat.zap_ticks_left = 0; predator.combat.zap_clock = 0
	before = player.health; predator.combat.attack(0.04)
	check(predator.combat.weapon.firing and player.health == before,"A Mutant can start a short burst from its original selection distance")
	check(predator.combat.weapon.beam_end.is_equal_approx(predator.global_position + Vector3.FORWARD * 1.8),"Starting a burst farther away does not extend the beam")
	player.position = predator.global_position + Vector3.FORWARD * 1.9
	await physics_frame
	predator.combat.zap_ticks_left = 0; predator.combat.zap_clock = 0
	before = player.health; predator.combat.attack(0.04)
	check(is_equal_approx(before - player.health,0.1),"The extended zapper hits a hull beyond the previous reach")
	player.position = predator.global_position + Vector3.FORWARD * 2.05
	await physics_frame
	predator.combat.zap_ticks_left = 0; predator.combat.zap_clock = 0
	before = player.health; predator.combat.attack(0.04)
	check(player.health == before,"A hull beyond the extended reach takes no zapper damage")
	player.position = predator.global_position + Vector3.FORWARD * 0.25
	await physics_frame

	predator.combat.settings["zapper_chance"] = 0
	predator.combat.zap_ticks_left = 0; predator.combat.zap_clock = 0
	predator.combat.bite_timer = 0
	before = player.health; predator.combat.attack(0.04)
	check(player.health == before,"An armed fish cannot bite between bursts")
	predator.combat.settings.zapper_range = 0.0
	predator.combat.attack(0.04)
	check(player.health == before,"An armed fish with zero zapper range cannot bite")

	predator.combat.settings.original_contact = true
	predator.combat.settings.contact_inflict = 1.0
	predator.velocity = Vector3.ZERO
	var closing_velocity := Vector3.BACK * 2
	check(is_zero_approx(predator.submarine_contact_damage(closing_velocity,Vector3.FORWARD)),"An armed fish cannot deal contact bite damage")
	predator.combat.settings.has_zapper = false
	check(predator.submarine_contact_damage(closing_velocity,Vector3.FORWARD) > 0.0,"Unarmed fish can still deal contact damage")
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
	await check_mutant_chase(folder)
	print("Wildlife combat: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func check_mutant_chase(folder: String) -> void:
	var assets := preload("res://clump_loader.gd")
	var template := Document.load_model("MUTANT",folder,true)
	var hull := assets.load_submarine(folder.path_join("CLUMPS/SUB.DFF"))
	check(template != null and hull != null,"Live chase fixture loads the original Mutant and submarine")
	if template == null or hull == null:
		if template != null: template.free()
		if hull != null: hull.free()
		return
	var arena := Node3D.new(); root.add_child(arena)
	arena.set_meta("bounds",AABB(Vector3.ONE * -100,Vector3.ONE * 200))
	arena.set_meta("surface_height",100.0)
	var wildlife := Population.new(); wildlife.world = arena; arena.add_child(wildlife)
	for index in range(1,4):
		wildlife.zapper_frames.append(assets._load_texture(folder,"ZAPPER%d" % index,"ZAPPER%dM" % index,{}))
	var camera := Camera3D.new(); arena.add_child(camera); camera.position = Vector3(4,2,5); camera.look_at(Vector3.ZERO); camera.current = true
	var pilot := preload("res://submarine_controller.gd").new()
	pilot.remember_settings = false; arena.add_child(pilot)
	pilot.active = true; pilot.freeze = true; pilot.surface_height = 100.0
	pilot.visual = hull; hull.rotation.y = PI; pilot.add_child(hull); pilot.fit_collision_to_visual()
	wildlife.player = pilot
	var boxes: Array[AABB] = []
	preload("res://creature_loader.gd")._collect_bounds(template,template.transform,boxes)
	var box := boxes[0]
	for bounds in boxes: box = box.merge(bounds)
	var species := {"id":"mutant","model":"MUTANT","response":"attack","speed":1.3,"group_behaviour":"solitary","mobility":"swimming"}
	var spawn := Vector3.BACK * 4.0
	var placement := {"point":spawn,"size":1.2,"radius":box.size.length() * 0.6,"member":0,"seed":42,"speed":1.0}
	var members: Array[Node3D] = []
	wildlife._create_member({"id":"mutant","radius":10.0},species,template,box,spawn,placement,members,preload("res://wildlife_shoal.gd").new(),[],false)
	var mutant := members[0]
	mutant.direction = Vector3.FORWARD
	for tick in range(360):
		await physics_frame
		if pilot.health < pilot.max_health and mutant.combat.weapon != null and mutant.combat.weapon.firing: break
	check(pilot.health < pilot.max_health and mutant.combat.weapon != null and mutant.combat.weapon.firing,"A naturally pursuing Mutant fires and damages the fitted player submarine")
	template.free()
	arena.free()
