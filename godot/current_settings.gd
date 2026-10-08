extends RefCounted
static func path(filename: String) -> String:
	if FileAccess.file_exists(ProjectSettings.globalize_path("res://project.godot")):
		return "res://".path_join(filename)
	var destination := "user://".path_join(filename)
	if not FileAccess.file_exists(destination):
		var source := FileAccess.open("res://".path_join(filename),FileAccess.READ)
		var target := FileAccess.open(destination,FileAccess.WRITE)
		if source != null and target != null: target.store_buffer(source.get_buffer(source.get_length()))
	return destination

static func migrate_legacy(movement_profile: String, sound_profile: String, directory: String = "") -> void:
	var view := ConfigFile.new(); view.load(path("view_defaults.cfg") if directory.is_empty() else directory.path_join("view_defaults.cfg"))
	var already_migrated := bool(view.get_value("settings","unified",false))
	for entry in [["view_defaults.cfg","user://opensubculture.cfg","view"],["submarine_tuning.cfg",movement_profile,"movement"],["submarine_audio.cfg",sound_profile,"sound"]]:
		var destination := path(entry[0]) if directory.is_empty() else directory.path_join(entry[0])
		var current := ConfigFile.new(); current.load(destination)
		if current.get_value("settings","unified",false): continue
		var legacy := ConfigFile.new()
		if not already_migrated and legacy.load(entry[1]) == OK and legacy.has_section(entry[2]):
			for key in legacy.get_section_keys(entry[2]): current.set_value(entry[2],key,legacy.get_value(entry[2],key))
		current.set_value("settings","unified",true)
		if current.save(destination) != OK: push_warning("Could not migrate current settings: " + destination)
