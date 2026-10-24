extends SceneTree
const Interface = preload("res://dock_interface.gd")
const Bindings = preload("res://input_bindings.gd")
var checks := 0
var failures := 0
var saved := {}
var slots: Array = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func pad(viewport: Viewport, button: int) -> void:
	var event := InputEventJoypadButton.new(); event.button_index = button; event.pressed = true
	viewport.push_input(event,true); event.pressed = false; viewport.push_input(event,true)
	await process_frame
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.gui_embed_subwindows = true; root.size = Vector2i(1280,720)
	Bindings.install(); Bindings.bindings = Bindings.defaults(); Bindings.apply_all()
	for index in range(7): slots.append({"slot":index,"name":"Empty slot","exists":false,"valid":false,"city":"","saved_at":""})
	var ui := Interface.new(); root.add_child(ui)
	paused = true
	ui.model = func() -> Dictionary: return {"city":"Touka Reef","slots":slots,"status":{},"autosave":{"valid":true,"saved_at":"2026-10-24T00:04:59"}}
	ui.action_requested.connect(func(action: String, payload: Dictionary) -> void:
		if action == "save_slot": saved = payload.duplicate()
	)
	ui.open("save"); await process_frame
	check(root.gui_get_focus_owner().name == "choose_slot_0","Save menu focuses the first slot")
	await pad(root,JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner().name == "choose_slot_1","D-pad moves directly between save slots")
	await pad(root,JOY_BUTTON_A)
	check(ui.name_dialog.visible and ui.name_field.text == "Save 2","Selecting an empty slot suggests its one-based save number")
	await pad(ui.name_dialog,JOY_BUTTON_A)
	check(not ui.name_dialog.visible and saved.get("slot") == 1 and saved.get("name") == "Save 2","Controller confirm accepts the numbered default and saves")
	slots[1] = {"slot":1,"name":"My voyage","exists":true,"valid":true,"city":"Touka Reef","saved_at":"2026-10-08T22:15:30"}
	ui.open("save"); ui._choose_slot(1); await process_frame
	check(ui.button_nodes.any(func(node: Button) -> bool: return node.text.contains("My voyage — 08/10/26 22:15") and node.tooltip_text == "Touka Reef — 08/10/26 22:15"),"Save list and tooltip use British date and 24-hour time without seconds")
	check(ui.name_field.text == "My voyage","Existing slots retain their saved name")
	await pad(ui.name_dialog,JOY_BUTTON_B)
	check(not ui.name_dialog.visible,"Controller cancel closes naming without saving")
	ui._choose_slot(1); await process_frame; await pad(ui.name_dialog,JOY_BUTTON_A)
	check(ui.overwrite_dialog.visible,"Controller saving an occupied slot asks before overwriting")
	await pad(ui.overwrite_dialog,JOY_BUTTON_B)
	check(not ui.overwrite_dialog.visible,"Controller cancel dismisses the overwrite prompt")
	ui._choose_slot(1); await process_frame; await pad(ui.name_dialog,JOY_BUTTON_A)
	ui.overwrite_dialog.get_ok_button().grab_focus(); await pad(ui.overwrite_dialog,JOY_BUTTON_A)
	check(saved.name == "My voyage" and saved.slot == 1,"Controller confirm completes an overwrite")
	ui.open("save"); ui.report("Saved.")
	await pad(root,JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner().name == "choose_slot_1","Slot navigation survives a menu refresh")
	ui.open("load")
	check(ui.button_nodes.any(func(node: Button) -> bool: return node.text.contains("My voyage — 08/10/26 22:15")),"Load list uses the same British timestamp")
	check(ui.button_nodes.any(func(node: Button) -> bool: return node.text == "Auto Save" and node.tooltip_text == "24/10/26 00:04"),"Autosave tooltip uses the same format including midnight")
	ui.open("save"); ui._choose_slot(6); await process_frame
	check(ui.name_field.text == "Save 7","Last slot defaults to Save 7")
	ui.name_field.text = "   "; ui._confirm_name()
	check(saved.slot == 6 and saved.name == "Save 7","Blank input falls back to the slot's numbered default")
	check(slots[1].name == "My voyage" and slots[1].saved_at == "2026-10-08T22:15:30","Formatting preserves existing custom names and stored ISO dates")
	check(preload("res://save_games.gd").display_timestamp("").is_empty() and preload("res://save_games.gd").display_timestamp("test") == "test","Missing or legacy non-date text is handled without parsing errors")
	paused = false; ui.free()
	print("Save menu input: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
