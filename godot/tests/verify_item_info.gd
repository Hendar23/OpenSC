extends SceneTree
const UI = preload("res://dock_interface.gd")
const Shop = preload("res://equipment_shop.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ",message)
	if not ok: failures += 1; push_error(message)
func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../dist/item-info-" + name + ".png")
func run() -> void:
	preload("res://input_bindings.gd").install()
	var folder := preload("res://asset_paths.gd").find_game_folder()
	var catalogue := preload("res://original_game_data.gd").load_catalogue(folder,false)
	var water: Dictionary = preload("res://commodity_market.gd").offers(catalogue,preload("res://player_progress.gd").restore(),"3").water
	var ripper := Shop.offer(catalogue,"1",1,"ripper")
	var ui := UI.new(); root.add_child(ui)
	var state := {"race":1,"city":"Beluga Basin","status":{"credits":10000},"offers":{},"hold":{},"installed":{},"commodity_offers":{"water":water},"cargo":{},"slots":[]}
	ui.setup(folder,func() -> Dictionary: return state)
	for race in [1,2,4]:
		state.race = race; ui.open("goods")
		var origin: Button = ui.layout.get_node("CommodityInfo"); origin.grab_focus()
		ui._show_item_info(water,"water")
		var panel: Control = ui.info_dialog.get_node("RepairInfo")
		check(panel.position == Vector2(34,30) and panel.size == Vector2(580,380),"Original popup bounds, race %d" % race)
		check(panel.get_node("ArtworkClip").position == Vector2(279,20) and panel.get_node("ArtworkClip").clip_contents,"Original clipped artwork panel")
		check(panel.get_node("ArtworkClip/Artwork").size == Vector2(282,300),"Water artwork keeps native size")
		check(panel.get_node("ItemName").text == "Purified Water" and panel.get_node("ItemName").position == Vector2(29,82),"Original commodity heading")
		check(panel.get_node("Description").text == water.description and panel.get_node("Description").position == Vector2(29,102),"Original description and text position")
		check(panel.get_node("ItemName").get_theme_color("font_color") == Color.WHITE and panel.get_node("Description").get_theme_color("font_color") == Color.YELLOW,"Original white heading and yellow description")
		check(not panel.has_node("Icon"),"Commodities keep the original empty icon space")
		var pixels: Image = panel.get_node("Frame").texture.get_image()
		check(pixels.get_pixel(300,100).a == 0 and pixels.get_pixel(100,100) == Color.BLACK,"Frame key exposes artwork and preserves black text panel")
		var prefix := "TP" if race in [2,4] else "TB"
		check(ui.info_done.held_art[0].texture == ui._button_texture(prefix + "-POPB") and ui.info_done.highlight_art[0].texture == ui._button_texture("ENGLISH/" + prefix + "-DN2"),"Original popup button assets, race %d" % race)
		check(ui.info_done.position == Vector2(24,313) and ui.info_done.highlight_art[0].rect.position + ui.info_done.position == Vector2(89,330),"Original Done positions")
		check(root.gui_get_focus_owner() == ui.info_done,"Controller focus stays in popup")
		check(ui.info_done.find_next_valid_focus() == ui.info_done and ui.info_done.find_prev_valid_focus() == ui.info_done,"Keyboard Tab focus stays in popup")
		await capture("water-%d" % race)
		check(panel.get_node("Description").size.x == 218 and panel.get_node("Description").get_line_count() > 1,"Description wraps inside the original text panel after rendering")
		ui.info_done.button_down.emit(); check(ui.info_done.held,"Mouse holds depressed state")
		await capture("water-held-%d" % race)
		ui.info_done.button_up.emit(); ui.info_done.pressed.emit()
		check(not ui.info_dialog.visible and root.gui_get_focus_owner() == origin and ui.page == "goods","Done returns focus to the unchanged shop")
	ui.open("equipment"); ui._show_item_info(ripper,"ripper")
	var panel: Control = ui.info_dialog.get_node("RepairInfo")
	check(panel.get_node("Icon").position == Vector2(30,31) and panel.get_node("Icon").texture != null,"Equipment uses its original square icon")
	check(panel.get_node("ArtworkClip/Artwork").size == Vector2(302,300),"Wide Ripper artwork is cropped rather than shrunk")
	await capture("ripper")
	var accept := InputEventJoypadButton.new(); accept.button_index = JOY_BUTTON_A; accept.pressed = true
	ui._input(accept); check(ui.info_done.held and ui.info_dialog.visible,"Controller confirm holds Done before release")
	accept.pressed = false; ui._input(accept)
	check(not ui.info_dialog.visible and ui.page == "equipment","Controller release closes only the popup")
	ui._show_item_info(ripper,"ripper")
	var cancel := InputEventJoypadButton.new(); cancel.button_index = JOY_BUTTON_B; cancel.pressed = true
	ui._input(cancel); check(not ui.info_dialog.visible and ui.page == "equipment","Controller cancel closes only the popup")
	ui._show_item_info(ripper,"ripper"); ui.rebuild()
	check(ui.info_dialog.visible and ui.layout.get_child(-1) == ui.info_dialog and root.gui_get_focus_owner() == ui.info_done,"Refresh keeps modal above the underlying page")
	ui.dismiss(); check(not ui.info_dialog.visible,"Leaving dock dismisses the popup")
	ui.queue_free(); await process_frame
	print("Item info: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
