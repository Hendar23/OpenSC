extends Node3D
## PIG00472700 and its10-shield rear control box00473110.
signal disabled
class Snout extends StaticBody3D:
	var robot: Node3D
	func take_weapon_damage(strength: float, _source: Vector3 = Vector3.ZERO) -> void:
		if strength > 0 and not robot.dead: robot.stalled = 4.0
	func take_damage(strength: float, source: Vector3 = Vector3.ZERO) -> void:
		take_weapon_damage(strength,source)
var game: Node
var model: Node3D
var power: RigidBody3D
var fan: StaticBody3D
var hull: StaticBody3D
var origin := Vector3.ZERO
var direction := 1.0
var travel := 0.0
var fan_speed := 0.0
var dead := false
var dying := -1.0
var smoke: Node3D
var snout: StaticBody3D
var stalled := 0.0

func setup(context: Node, visual: Node3D, control: RigidBody3D) -> void:
	game = context; model = visual; power = control; origin = global_position
	add_child(model)
	hull = StaticBody3D.new(); add_child(hull); hull.set_meta("contact_inflict",1.0)
	fan = StaticBody3D.new(); add_child(fan); fan.set_meta("contact_inflict",1.0)
	var blade: Node3D = model.get_node_or_null("Frame_0/Frame_1")
	if blade != null:
		fan.global_transform = blade.global_transform
		blade.reparent(fan,true)
	for root in [model,fan]:
		for mesh in root.find_children("*","MeshInstance3D",true,false):
			var body: StaticBody3D = fan if root == fan else hull
			var shape := CollisionShape3D.new(); shape.shape = mesh.mesh.create_trimesh_shape(); body.add_child(shape)
			shape.transform = body.global_transform.affine_inverse()*mesh.global_transform
	if power != null:
		power.reparent(self,true); power.freeze = true; power.towing_allowed = false
		power.destroyed.connect(_disable)
	# PIGSNOUT00473370 is an invisible, shootable 1.36-radius collider.
	# Hitting it briefly stalls the fan; the rear pack is the fatal weak point.
	snout = Snout.new(); snout.robot = self; add_child(snout)
	snout.position = Vector3(0,0,3.57); snout.collision_layer = 8; snout.collision_mask = 0
	var sphere := CollisionShape3D.new(); sphere.shape = SphereShape3D.new(); sphere.shape.radius = 1.36; snout.add_child(sphere)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON

func _disable() -> void:
	if dead: return
	dead = true; dying = 8.0
	snout.collision_layer = 0
	game.mission_runtime.side_jobs.burst(power.global_position,1)
	power.hide(); power.collision_layer = 0
	disabled.emit()
	smoke = preload("res://smoke_emitter.gd").new(); add_child(smoke)
	smoke.configure(game.game_folder,{"opacity":0.75,"start_size":0.2,"end_size":1.4})

func _physics_process(delta: float) -> void:
	if dead:
		fan_speed *= pow(0.85,delta*25)
		dying -= delta
		if dying <= 0:
			var demolition := preload("res://base_destruction.gd").new(); game.world_root.add_child(demolition)
			demolition.setup_vessel(self,game.submarine_traffic)
			queue_free(); return
	elif stalled > 0:
		stalled = maxf(0,stalled-delta); fan_speed *= pow(0.25,delta*25)
	else:
		fan_speed = minf(deg_to_rad(100),fan_speed+deg_to_rad(156.25)*delta)
		# .02 impulse /100 mass with .9 damping at25Hz.
		travel += direction*0.045*delta
		if travel >= 57: travel = 57; direction = -1
		elif travel <= 0: travel = 0; direction = 1
		global_position = origin+global_basis.z*travel
	fan.rotation.z = fposmod(fan.rotation.z+fan_speed*delta,TAU)
