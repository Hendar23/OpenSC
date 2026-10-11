extends SceneTree
const Fish = preload("res://fish_controller.gd")
const Assets = preload("res://clump_loader.gd")
const Creatures = preload("res://creature_loader.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func ray(fish: Node3D, from: Vector3, to: Vector3) -> Dictionary:
	return fish.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(fish.global_transform * from,fish.global_transform * to,8))
func run() -> void:
	var folder := ProjectSettings.globalize_path("res://../Original Sub Culture")
	for model in ["TURTLE","STINGRAY","JACKFISH"]:
		var template := Assets.load_clump(folder.path_join("CLUMPS/%s.DFF" % model),PackedStringArray(),true)
		check(template != null,"Original %s model loads" % model)
		if template == null: continue
		var boxes: Array[AABB] = []
		Creatures._collect_bounds(template,template.transform,boxes)
		var bounds := boxes[0]
		for box in boxes: bounds = bounds.merge(box)
		for size in [1.0,2.0]:
			var visual := template.duplicate() as Node3D
			visual.scale *= size; visual.position -= bounds.get_center() * size
			var fish := Fish.new()
			fish.setup(visual,Vector3.ZERO,AABB(Vector3.ONE * -100,Vector3.ONE * 200),100,bounds.size.length() * 0.5 * size,42)
			root.add_child(fish); fish.set_physics_process(false)
			check(fish.get_child(0).shape is ConvexPolygonShape3D,"%s uses a fitted hull at scale %s" % [model,size])
			fish.rotation = Vector3(0.2,0.7,0)
			await physics_frame; await physics_frame
			var reach := fish.radius + 1.0
			check(not ray(fish,Vector3(0,0,-reach),Vector3(0,0,reach)).is_empty(),"Ray through %s body hits after scaling and rotation" % model)
			var above: float = bounds.size.y * size * 0.5 + 0.04
			check(above < fish.radius,"Test ray is inside the old oversized sphere")
			check(ray(fish,Vector3(0,above,-reach),Vector3(0,above,reach)).is_empty(),"Empty space above %s is no longer a hit" % model)
			fish.free()
		template.free()
	var empty := Fish.new()
	empty.setup(Node3D.new(),Vector3.ZERO,AABB(),100,0.5,42)
	check(empty.get_child(0).shape is SphereShape3D,"Meshless placeholder retains a safe fallback")
	empty.free()
	print("Wildlife hitboxes: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
