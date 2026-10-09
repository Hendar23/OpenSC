extends SceneTree
const Movement = preload("res://movement_model.gd")
const Mods = preload("res://mod_registry.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	Mods.initialize(false,"res://tests/no-mods-fixture")
	var path := "res://tests/shared-movement-test.cfg"
	var export_path := "res://tests/mod-export-test.cfg"
	var config := ConfigFile.new(); config.set_value("movement","physics_version",2)
	config.set_value("movement","mass",100); config.set_value("movement","forward_speed",4.6); config.save(path)
	Mods.movement = {"mass":180.0,"impact_damage_scale":2.0}
	var movement := Movement.new(); movement.load_settings(false,path,path)
	check(movement.settings.mass == 180 and movement.settings.impact_damage_scale == 2,"Movement preset overlays existing shared settings")
	movement.settings.mass = 190; movement.settings.forward_speed = 7
	check(movement.save_settings() == OK,"Developer adjustments save to the same shared settings file")
	config.load(path)
	check(config.get_value("movement","mass") == 100 and config.get_value("movement","forward_speed") == 7,"Saving modded tuning preserves base mass and updates ordinary tuning")
	var reload := Movement.new(); reload.load_settings(false,path,path)
	check(reload.settings.mass == 190 and reload.settings.forward_speed == 7 and reload.settings.impact_damage_scale == 2,"Reload restores edits for the active preset")
	reload.save_settings(export_path); config.clear(); config.load(export_path)
	check(config.get_value("movement","mass") == 190 and not config.has_section(reload.mod_section),"Explicit export contains effective values without inactive profiles")
	Mods.movement = {}
	var disabled := Movement.new(); disabled.load_settings(false,path,path)
	check(disabled.settings.mass == 100 and disabled.settings.forward_speed == 7 and disabled.settings.impact_damage_scale == 1,"Disabling the preset restores base values without losing ordinary edits")
	disabled.save_settings()
	Mods.movement = {"mass":180.0,"impact_damage_scale":2.0}
	reload.load_settings(false,path,path)
	check(reload.settings.mass == 190,"Saving with the mod disabled preserves its adjustments for reactivation")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path)); DirAccess.remove_absolute(ProjectSettings.globalize_path(export_path))
	Mods.initialize(false)
	print("Movement mod settings: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
