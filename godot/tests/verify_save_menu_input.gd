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
	ui.model = func() -> Dictionary: return {"city":"Touka Reef","slots":slots,"status":{}}
	ui.action_requested.connect(func(action: String, payload: Dictionary) -> void:
		if action == "save_slot": saved = payload.duplicate()
	)
	ui.open("save"); await process_frame
	check(root.gui_get_focus_owner().name == "choose_slot_0","Save menu focuses the first slot")
	await pad(root,JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner().name == "choose_slot_1","D-pad moves directly between save slots")
	await pad(root,JOY_BUTTON_A)
	check(ui.name_dialog.visible and ui.name_field.text == "Touka Reef","Selecting an empty slot suggests the current city name")
	await pad(ui.name_dialog,JOY_BUTTON_A)
	check(not ui.name_dialog.visible and saved.get("slot") == 1 and saved.get("name") == "Touka Reef","Controller confirm accepts the suggested name and saves")
	slots[1] = {"slot":1,"name":"My voyage","exists":true,"valid":true,"city":"Touka Reef","saved_at":"2026-10-08T22:15:30"}
	ui.open("save"); ui._choose_slot(1); await process_frame
	check(ui.button_nodes.any(func(node: Button) -> bool: return node.text.contains("My voyage — 2026-10-08 22:15:30")),"Save list shows the name with its saved date and time")
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
	check(ui.button_nodes.any(func(node: Button) -> bool: return node.text.contains("My voyage — 2026-10-08 22:15:30")),"Load list also shows the saved date and time")
	paused = false; ui.free()
	print("Save menu input: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
