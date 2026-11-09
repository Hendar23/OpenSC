extends RefCounted
## Released endgame0046c350: group11, bomb delivery, iris and escape.
const Survivors = preload("res://mission_survivors.gd")
class Bomb extends "res://mission_prop.gd":
	func take_weapon_damage(strength: float, source: Vector3 = Vector3.ZERO) -> void:
		# Preserve a zero-sustain original/custom definition instead of treating
		# zero initial shields as an already-destroyed object on its first hit.
		if sustain <= 0: return
		super.take_weapon_damage(strength,source)

var jobs: Node
var helper: RefCounted
var site: Node3D
var bomb: RigidBody3D
var robot: Node3D
var iris: StaticBody3D
var button: StaticBody3D
var fire: Node3D
var enemies: Array[Node3D] = []
var guards: Array[Node3D] = []
var bomb_guards: Array[Node3D] = []
var allies: Array[Node3D] = []
var fish: Array[Node3D] = []
var arcs: Array[Node3D] = []
var electrode_start := {}
var electrode_end := {}
var destination := Vector3.ZERO
var escape_point := Vector3.ZERO
var bomb_capacity := 0.0
var age := 0.0
var poll := 0.0
var hazard_clock := 0.0
var dialogue := 0
var next_dialogue := 8.0
var taunt_at := 12.0
var warning := 0
var detonation := -1.0
var resolved := false
var retained := false
var radio_robot := false
var collected := false

func start() -> void:
	jobs.phase = "deliver"
	helper = preload("res://student_rescue.gd").new(); helper.jobs = jobs
	site = preload("res://mission_site.gd").new(); site.name = "ArmageddonSite"
	jobs.game.world_root.add_child(site); jobs.actors.append(site)
	site.stepped.connect(_hazards_step)
	_open_pipe()
	var rows: Array = jobs._rows(11)
	for row in rows:
		var pose: Transform3D = jobs._pose(row)
		match int(row.ObjectID):
			2: destination = pose.origin
			14: escape_point = pose.origin
			4:
				iris = preload("res://endgame_iris.gd").new(); site.add_child(iris); iris.global_transform = pose
				iris.setup(jobs.Document.load_model("ENDIRIS",jobs.game.game_folder,true))
			5: electrode_start[int(row.get("param1",0))] = pose.origin
			6: electrode_end[int(row.get("param1",0))] = pose.origin
	for row in rows:
		var pose: Transform3D = jobs._pose(row)
		match int(row.ObjectID):
			1: _robot(pose)
			3:
				button = preload("res://endgame_switch.gd").new(); site.add_child(button); button.global_transform = pose
				button.setup(jobs.Document.load_model("SWITCH",jobs.game.game_folder,true),iris)
			7,8:
				var enemy: Node3D = jobs._boat("PIRATE",pose,3,30,2.5)
				if enemy == null: continue
				enemy.engage_player = int(row.ObjectID) == 7
				# Preserve the pipe placements outside camera range. The outdoor
				# abstract traffic graph cannot represent these enclosed tunnels;
				# nearby pursuit uses the ordinary solid hull/terrain simulation.
				enemies.append(enemy)
				if int(row.ObjectID) == 7: guards.append(enemy)
				else: bomb_guards.append(enemy)
			9:
				var model: String = ["TECHNEW","TECH2SUB","TRAD-SUB","TRAD2"][randi_range(0,3)]
				var bohine := model in ["TRAD-SUB","TRAD2"]
				var ally: Node3D = jobs._boat(model,pose,1 if bohine else 2,10 if bohine else 15)
				if ally != null: allies.append(ally)
			10:
				var lamp := OmniLight3D.new(); site.add_child(lamp); lamp.global_position = pose.origin
				lamp.omni_range = 4; lamp.light_energy = 0.3; lamp.light_color = Color(1,0.4,0.15)
			12: _fish(pose.origin)
	_make_bomb()
	for index in bomb_guards.size():
		bomb_guards[index].combat_target = bomb
	for index in allies.size():
		if not bomb_guards.is_empty(): allies[index].combat_target = bomb_guards[index%bomb_guards.size()].body
	for index in electrode_start:
		if not electrode_end.has(index): continue
		var arc := preload("res://submarine_weapons.gd").create_arc(jobs.game.pilot,jobs.game.weapons.frames)
		site.add_child(arc); arc.set_physics_process(false); arc.camera = jobs.game.camera
		arc.beam_start = electrode_start[index]; arc.beam_end = electrode_end[index]
		arc.settings.beam_width = 0.03; arc.firing = true; arc.beam.show(); arcs.append(arc)
	jobs.game.natural_light.attach(site); jobs.game.water_visuals.attach(site)

func _open_pipe() -> void:
	for row in jobs.game.gameplay_catalogue.tables.get("database.objects",{}).get("records",{}).values():
		if int(row.get("MissionID",0)) == 2 and int(row.get("ObjectID",0)) == 5 and int(row.get("param2",-1)) == 2:
			site.mask(jobs.game.world_root.get_node_or_null("Scenery/PIPEBARS_%d"%int(row.index)))

func _make_bomb() -> void:
	var city := int(jobs.runtime.active().city)
	var point: Vector3 = jobs._city(city)
	for drop in jobs.game.get_tree().get_nodes_in_group("city_drop_off_points"):
		if drop.city_id == city: point = drop.global_position; break
	var definition: Dictionary = preload("res://object_definitions.gd").SALVAGE.duplicate(true)
	# Released OBJECTS.CSV MASSIVEBOMB:0 shields,0 sustain,.5 mass. The
	# controller's low-shield/failure branches still work with explicit overrides.
	definition.merge({"id":"armageddon_bomb","name":"MASSIVE","model":"MASSIVE","health":0.0,"mass":0.5,"magnet_compatible":true,"grapple_compatible":false,"suckomat_compatible":false,"delivery_commodity":"","delivery_quantity":0},true)
	bomb = Bomb.new(); bomb.sustain = 0
	bomb.setup(definition,jobs.Document.load_model("MASSIVE",jobs.game.game_folder),0,jobs.game.pilot.surface_height,true)
	site.add_child(bomb); bomb.global_position = point; bomb.freeze = true; bomb.release_on_tow = true
	bomb.set_meta("mission_owner",jobs.id); bomb.set_meta("mission_marker",true); bomb.set_meta("faction",0)
	bomb.destroyed.connect(_bomb_lost); bomb_capacity = bomb.health
	jobs.target = bomb; jobs.game.cockpit_hud.map_data.actor_markers.append(bomb)
	jobs.game.natural_light.attach(bomb); jobs.game.water_visuals.attach(bomb)

func _robot(pose: Transform3D) -> void:
	robot = preload("res://endgame_robot.gd").new(); site.add_child(robot); robot.global_transform = pose
	var power: RigidBody3D = helper.prop("PIGCTRL",pose*Transform3D(Basis.IDENTITY,Vector3(0,-1.36,-2.04)),10,0.5,100,false)
	jobs.actors.erase(power)
	robot.setup(jobs.game,jobs.Document.load_model("PIG",jobs.game.game_folder),power)
	robot.disabled.connect(_robot_disabled)

func _robot_disabled() -> void:
	if not resolved: jobs.radio("k11")

func _fish(point: Vector3) -> void:
	var builder := preload("res://stage_two_remaining.gd").new(); builder.jobs = jobs
	var body: Node3D = builder._fish("BLOWFISH",point,10,1,false,preload("res://fishbot.gd"))
	if body == null: return
	body.ignore_wildlife = true; body.traffic = jobs.game.submarine_traffic
	var no_blood: Array[Texture2D] = []
	body.death_frames = no_blood; body.death_sound = null; body.death_flesh_texture = null
	fish.append(body)

func step(delta: float) -> void:
	if resolved: return
	age += delta
	if detonation >= 0:
		if age-detonation >= 8 and jobs.game.pilot.global_position.x > escape_point.x:
			_ending(true,"campaign_escape")
		return
	if not is_instance_valid(bomb) or bomb.dead: return
	if not collected and jobs.game.equipment.magnet.target == bomb:
		collected = true; jobs.radio("k2")
	if bomb.global_position.distance_to(destination) < 3:
		_detonate(); return
	if age >= next_dialogue:
		match dialogue:
			0: jobs.radio("k1"); dialogue = 1; next_dialogue = age+4
			1:
				var ally: Node3D
				for ship in allies:
					if is_instance_valid(ship) and not ship.dead: ally = ship; break
				if ally == null or ally.global_position.distance_to(jobs.game.pilot.global_position) < 5:
					if ally != null: jobs.radio("k3" if int(ally.tuning.npc_faction) == 1 else "k4")
					dialogue = 2; next_dialogue = age+4
				else: next_dialogue = age+1
			2:
				if not is_instance_valid(robot) or robot.dead or robot.global_position.distance_to(jobs.game.pilot.global_position) < 8:
					if is_instance_valid(robot) and not robot.dead: jobs.radio("k10")
					dialogue = 3; next_dialogue = age+4
				else: next_dialogue = age+1
			3:
				if iris.global_position.distance_to(jobs.game.pilot.global_position) < 6:
					jobs.radio("k8"); dialogue = 4; next_dialogue = age+6
				else: next_dialogue = age+1
			4: jobs.radio("k9"); dialogue = 5; next_dialogue = INF
	if warning == 0 and bomb.health < bomb_capacity*0.1: warning = 2; jobs.radio("k13")
	elif warning < 1 and bomb.health < bomb_capacity*0.5: warning = 1; jobs.radio("k12")
	if age >= taunt_at:
		for enemy in guards:
			if is_instance_valid(enemy) and not enemy.dead and enemy.global_position.distance_to(jobs.game.pilot.global_position) < 8:
				jobs.radio("k%d"%randi_range(5,7)); break
		taunt_at = age+8
	poll -= delta
	if poll <= 0:
		poll = 0.1
		for ally in allies:
			if not is_instance_valid(ally) or ally.dead: continue
			if is_instance_valid(ally.combat_target) and ally.combat_target.get("dead") != true: continue
			for enemy in bomb_guards:
				if is_instance_valid(enemy) and not enemy.dead: ally.combat_target = enemy.body; break

func _hazards_step(delta: float) -> void:
	if not jobs.game.pilot.active or jobs.game.pilot.dead: return
	hazard_clock -= delta
	if hazard_clock > 0: return
	hazard_clock = 0.1
	for arc in arcs:
		var closest := Geometry3D.get_closest_point_to_segment(jobs.game.pilot.global_position,arc.beam_start,arc.beam_end)
		if closest.distance_to(jobs.game.pilot.global_position) < 0.6:
			jobs.game.pilot.take_weapon_damage(0.1*25*0.1,closest)

func _detonate() -> void:
	detonation = age; jobs.phase = "escape"
	bomb.delivered = true; bomb.dead = true; bomb.collision_layer = 0; bomb.collision_mask = 0; bomb.hide()
	jobs.game.equipment.reset_towing()
	jobs.radio("k15",true)
	if is_instance_valid(iris): iris.activate()
	fire = preload("res://endgame_fire.gd").new(); site.add_child(fire)
	fire.setup(jobs.game,iris.global_position+Vector3.DOWN*2)
	fire.caught.connect(_caught)
	# The retail sequence returns control to the sub and sacrifices a deployed ROV.
	var rover: Node3D = jobs.game.equipment.support_tools.rover
	if is_instance_valid(rover) and rover.launched:
		rover._lose()
	jobs.game.pilot.remote_controlled = false

func _caught() -> void:
	_ending(false,"antagonist_destroyed")

func _bomb_lost() -> void:
	if resolved or detonation >= 0: return
	jobs.radio("k14",true); resolved = true
	jobs.burst(bomb.global_position,3); bomb.hide()
	jobs._resolve(false,0,0)

func _ending(success: bool, cue: String) -> void:
	if resolved: return
	resolved = true
	var game: Node = jobs.game
	if is_instance_valid(fire): fire.finished = true
	jobs._resolve(success,1 if success else 0,0)
	game.events.fmv_requested.emit(cue,0)
	if not game.fmv.active: game._show_main_menu.call_deferred()

func target_body() -> CollisionObject3D:
	return bomb if is_instance_valid(bomb) and not bomb.dead and detonation < 0 else null

func release_survivors() -> void:
	Survivors.release(jobs,enemies)
	for ally in allies:
		if is_instance_valid(ally) and not ally.dead: Survivors.depart(jobs,ally)
	for body in fish:
		if is_instance_valid(body) and not body.dead:
			jobs.actors.erase(body); jobs.runtime.retain_scene_until_docking(body)
	if is_instance_valid(site):
		jobs.actors.erase(site); jobs.runtime.retain_scene_until_docking(site); retained = true
	resolved = true

func clear() -> void:
	if is_instance_valid(bomb) and bomb.destroyed.is_connected(_bomb_lost): bomb.destroyed.disconnect(_bomb_lost)
	if is_instance_valid(robot) and robot.disabled.is_connected(_robot_disabled): robot.disabled.disconnect(_robot_disabled)
	if is_instance_valid(fire) and fire.caught.is_connected(_caught): fire.caught.disconnect(_caught)
	if is_instance_valid(fire): fire.finished = true
	helper = null
