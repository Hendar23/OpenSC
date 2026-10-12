extends SceneTree
const Fish = preload("res://fish_controller.gd")
const Shoal = preload("res://wildlife_shoal.gd")
class PoseCounter extends RefCounted:
	var calls := 0
	var time := 0.0
	func apply(value: float) -> void:
		calls += 1; time = value
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var members: Array[Node3D] = []
	for index in range(3):
		var fish := Fish.new()
		fish.setup(Node3D.new(),Vector3(index * 2,0,0),AABB(Vector3.ONE * -100,Vector3.ONE * 200),100,0.5,index)
		root.add_child(fish); fish.direction = Vector3.FORWARD; members.append(fish)
	var shoal := Shoal.new(); shoal.refresh(members)
	check(shoal.center == Vector3(2,0,0) and shoal.alignment == Vector3.FORWARD,"Shared shoal snapshot preserves center and heading")
	check(shoal.separation(Vector3.ZERO,1.0) == Vector3.LEFT,"Separation retains radius and direction")
	members[2].position.x = 10; shoal.refresh(members)
	check(shoal.center == Vector3(2,0,0),"Repeated members reuse the same physics-tick snapshot")
	for fish in members: fish.set_physics_process(false); fish.set_process(false)
	await physics_frame
	members[2].set_meta("wildlife_awake",false); shoal.refresh(members)
	check(shoal.positions.size() == 2 and shoal.center == Vector3(1,0,0),"Next tick refreshes and excludes sleeping members")
	var large_group: Array[Node3D] = []
	for index in range(64):
		var member := Fish.new()
		member.position = Vector3((index % 8) * 1.1 - 4.0,0,(index / 8) * 1.1 - 4.0)
		large_group.append(member)
	var large_shoal := Shoal.new(); large_shoal.refresh(large_group)
	for point in [Vector3(-2.01,0,-2.01),Vector3(1.99,0,1.99)]:
		var expected := Vector3.ZERO
		for member in large_group:
			var away: Vector3 = point - member.position
			if away.length_squared() > 0.001 and away.length_squared() < 9.0: expected += away.normalized()
		check(large_shoal.separation(point,1.0).is_equal_approx(expected),"Large shoal separation matches full search across cell boundaries")
	for member in large_group: member.free()
	var fish = members[0]
	var population := preload("res://wildlife_population.gd").new()
	population._update_activity(fish,fish.global_position + Vector3(0,0,5),[])
	check(fish.animation_interval == 0.0,"Nearby wildlife selects full-rate animation")
	population._update_activity(fish,fish.global_position + Vector3(0,0,15),[])
	check(is_equal_approx(fish.animation_interval,1.0 / 30.0),"Middle-distance wildlife selects 30 Hz animation")
	population._update_activity(fish,fish.global_position + Vector3(0,0,25),[])
	check(is_equal_approx(fish.animation_interval,1.0 / 15.0),"Distant wildlife selects 15 Hz animation")
	population.free()
	var counter := PoseCounter.new(); fish.animation = counter
	fish._physics_process(1.0 / 60.0)
	check(counter.calls == 0 and fish.animation_time > 0,"Physics advances animation time without uploading a duplicate pose")
	fish.set_physics_process(true)
	fish.animation_interval = 1.0 / 15.0
	fish._process(0.0)
	check(counter.calls == 1,"First visible pose uploads immediately")
	for tick in range(60): fish._process(1.0 / 60.0)
	check(counter.calls == 16,"Distant fish upload 15 poses per second")
	fish.animation_interval = 1.0 / 30.0; fish.animation_elapsed = 0.0; counter.calls = 0
	for tick in range(60): fish._process(1.0 / 60.0)
	check(counter.calls == 30,"Middle-distance fish upload 30 poses per second")
	fish.animation_interval = 0.0; counter.calls = 0
	for tick in range(60): fish._process(1.0 / 60.0)
	check(counter.calls == 60,"Close fish upload every rendered frame")
	fish.animation_interval = 1.0 / 15.0; counter.calls = 0
	fish.visual_animation_enabled = false; fish._process(1.0)
	check(counter.calls == 0,"Offscreen fish upload no poses")
	fish.animation_time = 12.0; fish.visual_animation_enabled = true; fish._process(0.0)
	check(counter.calls == 1 and counter.time >= 12.0,"Returning fish immediately display their current animation phase")
	for member in members: member.free()
	print("Wildlife optimisation: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
