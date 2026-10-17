extends SceneTree
## Ordinary checks should not fill the checkout with converted asset files.
func _init() -> void:
	preload("res://asset_cache.gd").enabled = false

func _finalize() -> void:
	if "--keep-test-cache" in OS.get_cmdline_user_args(): return
	var storage_root: String = preload("res://player_storage.gd").root_override.simplify_path()
	if not storage_root.begins_with("res://tests/cache-") or not storage_root.ends_with("-fixtures"): return
	if storage_root.get_base_dir() != "res://tests": return
	for component in [storage_root,storage_root.path_join("cache"),storage_root.path_join("cache/assets")]:
		var parent := DirAccess.open(str(component).get_base_dir())
		if parent != null and parent.is_link(str(component).get_file()): return
	var target := ProjectSettings.globalize_path(storage_root.path_join("cache/assets")).simplify_path()
	var tests_root := ProjectSettings.globalize_path("res://tests").simplify_path().trim_suffix("/")+"/"
	if target.begins_with(tests_root): _remove_test_assets(target)

func _remove_test_assets(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry.to_lower().begins_with("readme"):
			push_warning("Test cache cleanup preserved protected documentation")
		elif directory.is_link(entry):
			push_warning("Test cache cleanup skipped symbolic link: "+path.path_join(entry))
		elif directory.current_is_dir(): _remove_test_assets(path.path_join(entry))
		else: directory.remove(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)
