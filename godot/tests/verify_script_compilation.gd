extends SceneTree
func _initialize() -> void:
	var checks := 0
	var failures := 0
	for filename in DirAccess.get_files_at("res://"):
		if not filename.ends_with(".gd"): continue
		checks += 1
		var script := ResourceLoader.load("res://" + filename,"GDScript",ResourceLoader.CACHE_MODE_IGNORE) as GDScript
		if script == null or not script.can_instantiate():
			failures += 1; push_error("Runtime script does not compile: " + filename)
	print("Runtime compilation: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
