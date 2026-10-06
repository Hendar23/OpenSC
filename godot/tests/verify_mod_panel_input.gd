extends SceneTree
const Mods = preload("res://mod_registry.gd")
var checks := 0
var failures := 0
var applied := false
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func click(panel: Window, control: Control) -> void:
	var point := control.get_global_rect().get_center() + Vector2(panel.position)
	var motion := InputEventMouseMotion.new(); motion.position = point; motion.global_position = point; root.push_input(motion,true)
	await process_frame
	for down in [true,false]:
		var event := InputEventMouseButton.new(); event.position = point; event.global_position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		root.push_input(event,true)
		await process_frame
	await process_frame
func button(panel: Window, label: String) -> Button:
	for node in panel.find_children("*","Button",true,false):
		if node.text == label: return node
	return null
func _run() -> void:
	root.gui_embed_subwindows = true; root.size = Vector2i(1280,720)
	Mods.initialize(false)
	var panel := preload("res://mod_panel.gd").new(); panel.persist_preferences = false
	root.add_child(panel); panel.applied.connect(func() -> void: applied = true)
	paused = true; panel.open()
	# A long in-memory list exercises scrolling without changing installed mods.
	Mods.packs.clear(); Mods.order.clear(); Mods.enabled.clear()
	for index in range(15):
		var id := "input-test-%d" % index
		Mods.order.append(id)
		Mods.packs.append({"id":id,"name":"Input test %d" % index,"version":"1.0","description":"Scrolling test description.","valid":true,"errors":[],"assets":{},"movement":{}})
	panel.open()
	for frame in range(5): await process_frame
	check(panel.can_process() and panel.choices.values()[0].can_process(),"Mod window and buttons receive input while main-menu gameplay is paused")
	await click(panel,panel.choices["input-test-0"])
	check("input-test-0" in panel.pending_enabled,"Mouse click toggles a mod while paused")
	await click(panel,button(panel,"Later"))
	check(panel.pending_order[1] == "input-test-0","Priority button changes order while paused")
	for frame in range(3): await process_frame
	var scroll: ScrollContainer = panel.rows.get_parent()
	var wheel := InputEventMouseButton.new(); wheel.position = scroll.get_global_rect().get_center(); wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed = true
	wheel.position += Vector2(panel.position); root.push_input(wheel,true)
	wheel.pressed = false; root.push_input(wheel,true); await process_frame
	check(scroll.scroll_vertical > 0,"Mouse wheel scrolls the mod list while paused")
	await click(panel,button(panel,"Cancel"))
	check(not panel.visible,"Cancel closes the paused mod window")
	panel.open(); for frame in range(3): await process_frame
	scroll.scroll_vertical = 0; await process_frame
	await click(panel,panel.choices["input-test-0"])
	await click(panel,button(panel,"Apply and reload"))
	check(applied and not panel.visible and "input-test-0" in Mods.enabled,"Apply commits selection and requests reload while paused")
	panel.open(); for frame in range(3): await process_frame
	await click(panel,button(panel,"Refresh installed mods"))
	check(not panel.pending_order.has("input-test-0") and panel.pending_order == Mods.order,"Refresh rescans installed mods while paused")
	paused = false; panel.queue_free(); await process_frame
	print("Mod panel input: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
