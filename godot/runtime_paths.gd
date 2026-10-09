extends RefCounted

## Editable content lives beside the game executable in exported builds.
static func external(path: String) -> String:
	if not OS.has_feature("editor") and path.begins_with("res://../"):
		return OS.get_executable_path().get_base_dir().path_join(path.trim_prefix("res://../"))
	return ProjectSettings.globalize_path(path)
