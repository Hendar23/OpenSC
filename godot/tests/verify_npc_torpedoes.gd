extends SceneTree
const Missile = preload("res://turret_missile.gd")
var checks := 0
var failures := 0
class Trail extends Node3D:
	var credits := {}
	var emissions := 0
	func emit_from(id: int, _point: Vector3, _direction: Vector3, _power: float, _rate: float, _delta: float) -> void:
		credits[id] = 1.0; emissions += 1
class Shooter extends Node3D:
	var bubble_trail: Node3D
	var hitbox: Node3D
	var explosion_frames: Array[Texture2D] = []
	var explosion_sound: AudioStream
	var bursts := 0
	var last_burst := Vector3.ZERO
	func burst(point: Vector3, _size: float) -> void:
		bursts += 1; last_burst = point
class Target extends Node3D:
	var dead := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	for guided in [false,true]:
		var viewport := SubViewport.new(); viewport.own_world_3d = true; root.add_child(viewport)
		var ocean := Node3D.new(); viewport.add_child(ocean)
		var floor_body := StaticBody3D.new(); floor_body.collision_layer = 1; ocean.add_child(floor_body)
		var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(200,0.5,200); shape.shape = box; floor_body.add_child(shape)
		var trail := Trail.new(); ocean.add_child(trail); trail.credits[-123] = 1.0
		var shooter := Shooter.new(); shooter.bubble_trail = trail; ocean.add_child(shooter)
		var target := Target.new(); ocean.add_child(target); target.position = Vector3(0,6,-100)
		var template := Node3D.new()
		var shot := Missile.new(); ocean.add_child(shot)
		shot.setup(shooter,template,Vector3(0,6,0),Vector3.FORWARD,target,guided)
		template.free(); shot.set_physics_process(false)
		await physics_frame; await physics_frame
		var expected := 0.0; var speed := 0.0
		for tick in range(133):
			speed = (speed+0.0025/0.1*25.0)*Missile.DAMPING; expected += speed/25.0
			shot._physics_process(0.04)
		check(not shot.out_of_fuel and is_equal_approx(-shot.position.z,expected),"NPC powered flight keeps its previous speed and reach; guided="+str(guided))
		var emissions := trail.emissions
		shot._physics_process(0.04)
		check(shot.out_of_fuel and not shot.spent and not shot.is_queued_for_deletion(),"Fuel expiry retains the projectile; guided="+str(guided))
		check(shot.target == null and not trail.credits.has(shot.get_instance_id()) and trail.credits.has(-123),"Fuel expiry stops homing and only clears this projectile's emitter")
		var pose := shot.basis; var altitude := shot.position.y
		target.position.x = 50
		for tick in range(25): shot._physics_process(0.04)
		check(shot.position.y < altitude and not shot.basis.is_equal_approx(pose),"Spent torpedo tumbles downward")
		check(trail.emissions == emissions and shooter.bursts == 0,"Spent torpedo stops bubbles and does not explode in mid-water")
		for tick in range(500):
			if shot.spent: break
			shot._physics_process(0.04)
		check(shot.spent and shooter.bursts == 1 and absf(shooter.last_burst.y-0.25) < 0.01,"Spent torpedo explodes once on actual sea-floor collision")
		shot._physics_process(0.04)
		check(shooter.bursts == 1,"Queued projectile cannot explode twice")
		await process_frame
		var orphan := Missile.new(); ocean.add_child(orphan)
		var orphan_template := Node3D.new()
		orphan.setup(shooter,orphan_template,Vector3(0,1,0),Vector3.FORWARD,target,guided)
		orphan_template.free()
		orphan.set_physics_process(false); orphan.age = Missile.LIFETIME; shooter.free()
		for tick in range(300):
			if orphan.spent: break
			orphan._physics_process(0.04)
		check(orphan.spent and ocean.find_child("MineExplosion",true,false) != null,"Spent projectile still explodes if its launcher has been removed")
		viewport.free()
	print("NPC torpedoes: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
