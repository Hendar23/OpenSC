extends RefCounted
## Applies developer tuning values to HUD, equipment, weapons, and docking.

var game: Node3D

func _init(context: Node3D) -> void:
	game = context

const Docking = preload("res://docking_controller.gd")

func _update_hud_settings() -> void:
	if game.crt_reflection_slider != null:
		game.crt_reflection_label.text = "CRT reflection strength: %.0f%%" % game.crt_reflection_slider.value
		if game.cockpit_hud != null: game.cockpit_hud.crt_reflection_strength = game.crt_reflection_slider.value / 100.0
	if game.hud_map_zoom_slider != null:
		game.hud_map_zoom_label.text = "Minimap zoom: %.1f×" % game.hud_map_zoom_slider.value
		if game.cockpit_hud != null: game.cockpit_hud.map_zoom = game.hud_map_zoom_slider.value
	if game.map_reveal_slider != null:
		game.map_reveal_label.text = "Minimap reveal radius: %.1f units" % game.map_reveal_slider.value
		if game.cockpit_hud != null: game.cockpit_hud.map_data.reveal_radius = game.map_reveal_slider.value

func _update_equipment_settings() -> void:
	if game.equipment == null: return
	for key in game.equipment_controls: game.equipment.settings[key] = game.equipment_controls[key].value
	game.equipment.apply_settings()

func _update_weapon_settings() -> void:
	if game.weapons == null: return
	var values := {}
	for key in game.weapon_controls: values[key] = game.weapon_controls[key].value
	game.weapons.configure(values)
	for key in game.weapon_controls: game.weapon_controls[key].get_meta("label").text = "%s: %.2f" % [game.weapon_controls[key].get_meta("caption"),game.weapon_controls[key].value]

func _update_docking_radius() -> void:
	game.docking_radius_label.text = "Docking prompt radius: %.1f units" % game.docking_radius_slider.value
	if game.docking != null:
		game.docking.approach_radius = game.docking_radius_slider.value
		game.docking.update_approach()
