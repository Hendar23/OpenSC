extends RefCounted
## Release options are fallbacks; existing player preferences always win.
const PATH := "res://release_options.cfg"
const SECTIONS := ["gameplay","graphics","audio"]

static func load_preferences(path: String) -> ConfigFile:
	var result := ConfigFile.new()
	if FileAccess.file_exists(PATH): result.load(PATH)
	var personal := ConfigFile.new()
	if personal.load(path) == OK:
		for section in SECTIONS:
			if not personal.has_section(section): continue
			# Older saved option sections retain their original built-in
			# fallbacks for newly introduced keys, as well as their saved values.
			if result.has_section(section): result.erase_section(section)
			for key in personal.get_section_keys(section): result.set_value(section,key,personal.get_value(section,key))
	return result
