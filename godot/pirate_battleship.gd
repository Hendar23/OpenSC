extends RefCounted
## Shared original BOSS hull and its two separately destructible gun mounts.

static func install(jobs: Node, boss: Node3D) -> Array[Node3D]:
	var guns: Array[Node3D] = []
	var hull := StaticBody3D.new(); boss.add_child(hull)
	for module in [{"point":Vector3(0,-0.3,1.6),"radius":0.7},{"point":Vector3(0,-0.1,0.2),"radius":1.4},{"point":Vector3(0,-0.1,-1.3),"radius":1.5},{"point":Vector3(0,0,-2.1),"radius":1.2}]:
		var shape := CollisionShape3D.new(); var sphere := SphereShape3D.new()
		sphere.radius = module.radius; shape.shape = sphere; shape.position = module.point; hull.add_child(shape)
	# The original exposes six sphere modules. Only the last two have
	# nonzero sustain: 20 health, 0.5 sustain, radius 0.7 / 0.5.
	for spec in [{"frame":"Frame_1","head":"Frame_5","point":Vector3(0,1.2,0.1),"radius":0.5},{"frame":"Frame_3","head":"Frame_4","point":Vector3(0,-1.2,-2.5),"radius":0.7}]:
		var model := Node3D.new(); boss.add_child(model)
		var frame: Node3D = boss.find_child(spec.frame,true,false)
		if frame != null: frame.reparent(model,true)
		var body := StaticBody3D.new(); body.name = "SceneryCollision"; model.add_child(body)
		var shape := CollisionShape3D.new(); var sphere := SphereShape3D.new(); sphere.radius = spec.radius
		shape.shape = sphere; shape.position = spec.point; body.add_child(shape)
		var gun := preload("res://diplomat_boss_gun.gd").new(); gun.name = "GunTurret"; model.add_child(gun)
		gun.head = model.find_child(spec.head,true,false); gun.hitbox = body
		if spec.head == "Frame_4":
			# Retail lower gun sockets point down its local -Z axis.
			gun.barrel_sign = -1.0; gun.muzzles.assign([Vector3(0.35,-0.4,-1),Vector3(-0.35,-0.4,-1)])
		body.set_script(preload("res://turret_hitbox.gd")); body.set_meta("damage_sustain",0.5)
		gun.tuning.merge({"turret_health":20.0,"turret_sustain":0.5,"turret_armed":true},true)
		gun.health = 20; gun.player = jobs.game.pilot
		gun.missile_template = jobs.Document.load_model("MISSILE",jobs.game.game_folder)
		if gun.missile_template != null:
			gun.add_child(gun.missile_template); gun.missile_template.hide()
			gun.missile_template.set_meta("exclude_from_debris",true)
		gun.bubble_trail = jobs.game.submarine_traffic.bubbles
		gun.bubble_texture = jobs.game.submarine_traffic.bubble_texture
		gun.explosion_frames = jobs.game.submarine_traffic.explosion_frames; gun.explosion_sound = jobs.game.submarine_traffic.explosion_sound
		guns.append(gun)
	return guns
