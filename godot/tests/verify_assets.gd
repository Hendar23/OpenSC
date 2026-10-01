extends SceneTree

const Assets = preload("res://clump_loader.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var folder := preload("res://asset_paths.gd").find_game_folder().path_join("CLUMPS")
	var names := DirAccess.get_files_at(folder)
	var failed: Array[String] = []
	var count := 0
	for name in names:
		if name.get_extension().to_upper() != "DFF": continue
		count += 1
		var model := Assets.load_clump(folder.path_join(name), PackedStringArray(), true)
		if model == null: failed.append(name)
		else: model.free()
	print("Assets checked: %d; failed: %s" % [count, str(failed)])
	quit(0 if failed.is_empty() else 1)
