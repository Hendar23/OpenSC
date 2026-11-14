extends RefCounted
## Retail backstab variants: SC.EXE0047b740; placement group28.
const Mine = preload("res://floating_mine.gd")
var jobs: Node
var ship: RigidBody3D
var mines: Array[Node3D] = []
var watched: Array[Node3D] = []
var jammed := false
var freed := false
var finished := false
var cover_escape := false
var found := false
var warned := false
var laughed := false
var blast_hits := 0
var clock := 0.0
var taunt_clock := 20.0
var taunt := 3
var explosion_at := -1.0
var success_at := -1.0
var escape_taunt_at := -1.0
var start_help := 2.8
var builder: RefCounted

func start() -> void:
	jobs.phase = "search"
	builder = preload("res://student_rescue.gd").new(); builder.jobs = jobs
	var mine_builder := preload("res://stage_three_missions.gd").new(); mine_builder.jobs = jobs
	for row in jobs._rows(28):
		var pose: Transform3D = jobs._pose(row)
		if int(row.ObjectID) == 1:
			# The released callback always creates object20, TECHSHUT, even
			# for the Procha briefings describing a Bohine vessel.
			ship = builder.prop("TECHSHUT",pose,50,0.5,5,true)
			builder.place_clear(ship); ship.freeze = true; ship.release_on_tow = true
			ship.set_meta("mission_delivery",true); jobs.target = ship
			ship.destroyed.connect(_destroyed); ship.damaged.connect(_shot)
		elif int(row.ObjectID) == 2:
			for index in range(12):
				var point := pose.origin+Vector3(randi_range(-16,15)*0.7,0,randi_range(-16,15)*0.7)
				var top := Vector3(point.x,jobs.game.pilot.surface_height,point.z)
				var bottom := Vector3(point.x,jobs.game.world_root.get_meta("bounds").position.y-1,point.z)
				var query := PhysicsRayQueryParameters3D.create(top,bottom,1); query.hit_back_faces = true
				var hit: Dictionary = jobs.game.get_world_3d().direct_space_state.intersect_ray(query)
				point.y = (top.y+float(hit.position.y))*0.5 if not hit.is_empty() else pose.origin.y
				mine_builder._mine(Transform3D(Basis.IDENTITY,point),false)
	mines.assign(mine_builder.mines)
	for mine in mines: mine.exploded.disconnect(Callable(mine_builder,"_mine_blast"))
	for node in jobs.game.world_root.find_children("*","StaticBody3D",true,false):
		if node is Mine:
			node.exploded.connect(_blast); watched.append(node)

func _blocked() -> bool:
	return jammed and not finished and is_instance_valid(ship) and not ship.dead and not jobs.game.pilot.dead

func step(delta: float) -> void:
	if finished: return
	clock += delta
	if not is_instance_valid(ship): return
	var magnet: Node3D = jobs.game.equipment.magnet
	var previous_help := start_help
	start_help -= delta
	if previous_help > 0 and start_help <= 0: jobs.radio("ab2")
	if not found and clock >= 2 and ship.global_position.distance_squared_to(jobs.game.pilot.global_position) < 10:
		found = true; jobs.radio("ab1")
	if not jammed and not freed and magnet.target == ship:
		jammed = true; jobs.phase = "trapped"; jobs.radio("ab12")
		magnet.release_guard = _blocked; taunt_clock = 20
	if jammed:
		taunt_clock -= delta
		while taunt_clock <= 0 and taunt <= 9:
			jobs.radio("ab%d" % taunt)
			if taunt == 9: explosion_at = clock+taunt_clock+1.6
			taunt += 1; taunt_clock += 16
		if is_instance_valid(magnet.head):
			for mine in watched:
				if not jammed: break
				if is_instance_valid(mine) and not mine.dead and mine.global_position.distance_to(magnet.head.global_position) < float(mine.stats.size)*0.5+0.15: mine.detonate()
	if explosion_at >= 0 and clock >= explosion_at and not ship.dead:
		ship.take_weapon_damage(100000)
	if escape_taunt_at >= 0 and clock >= escape_taunt_at:
		escape_taunt_at = -1; jobs.radio("ab10",cover_escape)
	if success_at >= 0 and clock >= success_at and not finished:
		finished = true
		if not cover_escape: jobs.radio("ab13",true)
		jobs._resolve(true,1,1)

func _blast(point: Vector3, _damage: float, _radius: float) -> void:
	if not jammed or not is_instance_valid(ship) or ship.dead: return
	var magnet: Node3D = jobs.game.equipment.magnet
	if not is_instance_valid(magnet.head): return
	var head_distance: float = point.distance_squared_to(magnet.head.global_position)
	if head_distance < 1.7 or point.distance_squared_to(ship.global_position) < 1.7:
		blast_hits += 1
		if blast_hits >= 2:
			jammed = false; freed = true; jobs.phase = "escaped"
			magnet.release_guard = Callable(); magnet.set_enabled(false)
			explosion_at = clock+11.2; success_at = clock+12; escape_taunt_at = clock+6
	elif head_distance < 3 and not laughed:
		laughed = true; jobs.radio("ab11")

func _shot() -> void:
	if not jammed and not freed and not warned: warned = true; jobs.radio("ab16")

func _destroyed() -> void:
	if finished: return
	var point := ship.global_position
	jobs.burst(point,3)
	var player: Node3D = jobs.game.pilot
	var query := PhysicsRayQueryParameters3D.create(point,player.global_position,1,[ship.get_rid()]); query.hit_back_faces = true
	var exposed: bool = jobs.game.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	var trapped := jammed
	jammed = false; jobs.game.equipment.magnet.release_guard = Callable()
	if jobs.game.equipment.magnet.target == ship: jobs.game.equipment.magnet.set_enabled(false)
	ship.hide()
	if exposed:
		# Retail writes hull health directly: protection cannot absorb this trap.
		var damage = preload("res://original_damage.gd")
		var loss: float = player.health if trapped else player.health*0.5
		player.take_damage(loss*damage.BASE_SUSTAIN/maxf(0.0001,damage.sustain(player.hull_rating)),point)
	elif trapped:
		# Retail47b740 also permits escaping the blast behind solid terrain.
		freed = true; cover_escape = true; success_at = clock+6; escape_taunt_at = clock+6
	if not freed:
		# RESPONSE2 is an unused developer placeholder in the shipped text.
		finished = true; jobs.radio("ab15",true); jobs._resolve(false,0,0)

func delivery_cities(body: Node3D) -> Variant:
	return [] if body == ship else null

func delivery(body: Node3D, _city: int) -> bool:
	if body != ship: return false
	jobs.radio("ab14"); jobs.game.equipment.magnet.decline_delivery(); return true

func target_body() -> CollisionObject3D:
	return ship if is_instance_valid(ship) and not ship.dead else null

func clear() -> void:
	jammed = false
	var magnet: Node3D = jobs.game.equipment.magnet
	if magnet.release_guard == Callable(self,"_blocked"): magnet.release_guard = Callable()
	if is_instance_valid(ship):
		if magnet.target == ship: magnet.set_enabled(false)
		if ship.destroyed.is_connected(_destroyed): ship.destroyed.disconnect(_destroyed)
		if ship.damaged.is_connected(_shot): ship.damaged.disconnect(_shot)
	for mine in watched:
		if is_instance_valid(mine) and mine.exploded.is_connected(_blast): mine.exploded.disconnect(_blast)
	watched.clear(); builder = null
