extends RefCounted

static func path(filename: String, directory: String = "") -> String:
	return ("res://" if directory.is_empty() else directory).path_join(filename)
