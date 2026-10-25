extends RefCounted
## Expanded map construction and visibility.

var game: Node3D

func _init(context: Node3D) -> void:
	game = context


func _build_expanded_map() -> void:
	game.map_overlay = CanvasLayer.new(); game.map_overlay.layer = 50; game.add_child(game.map_overlay)
	var backdrop := ColorRect.new(); backdrop.color = Color(0.002,0.005,0.015)
	game.map_overlay.add_child(backdrop); backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.map_screen = preload("res://map_screen.gd").new(); game.map_overlay.add_child(game.map_screen)
	game.map_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.map_screen.setup(game.pilot,game.cockpit_hud.map_data,game.gameplay_catalogue,game._map_ui_model)
	game.expanded_map = game.map_screen.map
	game.map_overlay.hide()

func _map_ui_model() -> Dictionary:
	return {"credits":game.player_progress.status.credits,"cargo":game.player_progress.cargo.duplicate(),"hold":game.player_progress.hold.duplicate()}

func _set_map_open(open: bool) -> void:
	game.map_open = open and game.map_overlay != null
	if game.map_overlay != null: game.map_overlay.visible = game.map_open
	if game.map_open and game.pilot != null: game.pilot.controls_enabled = false
	if game.map_open and game.weapons != null: game.weapons.update_fire(false,0)
	game._update_mouse_pointer()
