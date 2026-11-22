extends RefCounted
## Languages supplied by the original retail data, independent of the installer.

const DIRECTORIES := {"en":"ENGLISH", "fr":"FRENCH", "de":"GERMAN"}
const NAMES := {"en":"English", "fr":"Français", "de":"Deutsch"}

class LiveLabel extends Label:
	var message := ""
	var arguments: Array = []

	func set_message(key: String, values: Array) -> void:
		message = key
		arguments = values
		_refresh()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_TRANSLATION_CHANGED and not message.is_empty():
			_refresh()

	func _refresh() -> void:
		var localized := arguments.map(func(value: Variant) -> Variant:
			return tr(value) if value is String else value)
		text = tr(message) % localized

static func available(folder: String) -> Array[String]:
	var result: Array[String] = []
	if folder.is_empty(): return result
	for locale in DIRECTORIES:
		if FileAccess.file_exists(folder.path_join(archive_path(folder, locale))): result.append(locale)
	return result

static func preferred(folder: String, locales: Array[String], requested: String = "") -> String:
	if requested in locales: return requested
	var system := OS.get_locale_language()
	if system in locales: return system
	var original := _configured_language(folder)
	if original in locales: return original
	return locales[0] if not locales.is_empty() else "en"

static func saved(config_path: String) -> String:
	var config := ConfigFile.new()
	if config.load(config_path) != OK: return ""
	return str(config.get_value("game", "language", ""))

static func text(message: String, locale: String) -> String:
	if locale == "en": return message
	var translation := TranslationServer.get_translation_object(locale)
	if translation == null: return message
	var localized := String(translation.get_message(message))
	return message if localized.is_empty() else localized

static func archive_path(folder: String, locale: String) -> String:
	var relative := "DATA/%s/LANGUAGE.ENC" % DIRECTORIES.get(locale, "ENGLISH")
	if not FileAccess.file_exists(folder.path_join(relative)) and _configured_language(folder) == locale:
		if FileAccess.file_exists(folder.path_join("DATA/LANGUAGE.ENC")): return "DATA/LANGUAGE.ENC"
	return relative

static func asset(folder: String, area: String, filename: String, locale: String = "en") -> String:
	var base := folder.path_join(area)
	var localized := base.path_join(str(DIRECTORIES.get(locale, "ENGLISH"))).path_join(filename)
	if FileAccess.file_exists(localized): return localized
	return base.path_join(filename)

static func _configured_language(folder: String) -> String:
	for relative in ["LANGUAGE.CFG", "DATA/LANGUAGE.CFG"]:
		var path := folder.path_join(relative)
		if not FileAccess.file_exists(path): continue
		var name := FileAccess.get_file_as_string(path).strip_edges().to_upper()
		for locale in DIRECTORIES:
			if DIRECTORIES[locale] == name: return locale
	return ""
