extends SceneTree
const Mail = preload("res://mailbox.gd")
const Progress = preload("res://player_progress.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	preload("res://asset_cache.gd").enabled = false
	call_deferred("run")
func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/mailbox-" + name + ".png")
func run() -> void:
	preload("res://input_bindings.gd").install()
	var folder := preload("res://asset_paths.gd").find_game_folder()
	var catalogue := preload("res://original_game_data.gd").load_catalogue(folder,false)
	var records: Dictionary = catalogue.tables.mail_messages.records
	check(records.size() > 60,"Original bulletin texts imported")
	check(records["220"].subject == "BTV News: Submarine Missing","Original mail subject")
	check(records["220"].body.contains("Bacau") and not records["220"].body.contains("#mission") and not records["220"].body.contains("Rescue Bacau Shuttle"),"Message stops before next mission section")
	check(records["220"].body.contains("\n\n") and not records["220"].body.contains("<p>"),"Original paragraphs decode")
	var progress := Progress.restore()
	check(Mail.messages(catalogue,progress,1).is_empty(),"Original zero-based stage counter gives no starting oyster mail")
	Mail.set_mission_available(progress,"stranded")
	var messages := Mail.messages(catalogue,progress,1)
	check(messages.size() == 1 and messages[0].id == "220" and not messages[0].read,"Available mission delivers original advance news")
	check(Mail.messages(catalogue,progress,2).is_empty(),"Bohine news excluded from Procha dock")
	check(Mail.messages(catalogue,progress,3).size() == 1,"Mail available across appropriate faction")
	Mail.mark_read(progress,"220")
	progress = Progress.restore(JSON.parse_string(JSON.stringify(progress)))
	check(Mail.messages(catalogue,progress,1)[0].read,"Read status and delivery survive JSON save round trip")
	Mail.mission_completed(progress,"stranded",0.95)
	messages = Mail.messages(catalogue,progress,1)
	check(messages.any(func(m: Dictionary) -> bool: return m.id == "221") and not messages.any(func(m: Dictionary) -> bool: return m.id == "226" or m.id == "220"),"Original post-news score boundaries and pre-mail expiry")
	progress.campaign_stage = 2; progress.campaign_jobs = 0
	check(Mail.messages(catalogue,progress,3).any(func(m: Dictionary) -> bool: return m.id == "1002"),"Oyster hint begins at campaign stage two, original internal stage one")
	check(not Mail.messages(catalogue,progress,3).any(func(m: Dictionary) -> bool: return m.id == "1001"),"Metal hint waits for its completed-job threshold")
	progress.campaign_jobs = 2
	check(Mail.messages(catalogue,progress,3).any(func(m: Dictionary) -> bool: return m.id == "1001"),"Campaign hint uses stage/job threshold")
	check(not Mail.messages(catalogue,progress,2).any(func(m: Dictionary) -> bool: return m.id == "1000"),"Later hint is not delivered early")
	check(Mail.restore({"received":{"x":{},"123":{"read":"yes","order":INF}},"available":[4],"outcomes":{"bad":NAN}}) == {"received":{"123":{"read":false,"order":0}},"available":[],"outcomes":{}},"Malformed saved mail safely normalised")
	check(Progress.restore(null).has("mail"),"Malformed/legacy save gets mailbox defaults")
	var ui := preload("res://dock_interface.gd").new(); root.add_child(ui)
	var state := {"city":1,"race":1}
	ui.setup(folder,func() -> Dictionary: return {"city_id":str(state.city),"city":"Touka Reef","race":state.race,"status":{},"welcome":"Welcome.","mail":Mail.messages(catalogue,progress,state.city)})
	ui.action_requested.connect(func(action: String,payload: Dictionary) -> void:
		if action == "read_mail": Mail.mark_read(progress,payload.id))
	ui.open("home")
	check(ui.mail_button.position == Vector2(100,203) and ui.mail_button.normal_art.size() == 1,"Original mailbox button artwork and position")
	check(ui.layout.has_node("UnreadMail"),"Unread notification on dock screen")
	check(ui.layout.get_node("UnreadEnvelope").position == Vector2(269,218) and not ui.layout.get_children().any(func(node: Node) -> bool: return node is TextureRect and node.position == Vector2(232,12)),"Unread envelope stays beside the mail count without overlapping the city title")
	ui.mail_button.pressed.emit()
	check(ui.mail_view == "list" and ui.mail_list.item_count > 0,"Mailbox toggle shows available message list")
	await capture("list")
	var id := str(ui.mail_rows[0].id)
	ui._read_mail(0)
	check(ui.mail_view == "read" and ui.mail_body.text == records[id].body and progress.mail.received[id].read,"Reading displays full original body and marks read")
	check(ui.mail_body.size == Vector2(412,98),"Original six-line body region with overflow scrolling")
	await capture("read")
	ui.mail_button.pressed.emit()
	check(ui.mail_view == "list" and ui.mail_list.get_item_text(0).begins_with("# "),"Original read marker and return to list")
	ui.mail_list.grab_focus(); ui.mail_list.select(0)
	var down := InputEventAction.new(); down.action = "menu_down"; down.pressed = true
	ui._input(down)
	check(ui.mail_view == "list" and ui.mail_list.get_selected_items()[0] == 1,"Controller can browse without opening every message")
	var accept := InputEventAction.new(); accept.action = "menu_accept"; accept.pressed = true
	ui._input(accept)
	check(ui.mail_view == "read","Controller accept opens selected mail")
	var cancel := InputEventAction.new(); cancel.action = "menu_cancel"; cancel.pressed = true
	ui._input(cancel)
	check(ui.mail_view == "list","Controller back returns to mailbox")
	ui._input(cancel)
	check(ui.mail_view == "welcome","Controller back returns to city welcome")
	ui.mail_button.pressed.emit()
	for r in [1,2,4]:
		state.race = r; ui.rebuild()
		check(ui.mail_button.highlight_art.size() == 1 and ui.mail_button.held_art.size() == 1,"Faction mail button states %d" % r)
		ui.mail_button.held = true; ui.mail_button.queue_redraw(); await capture("race-%d-held" % r)
	state.city = 2; ui.open("home")
	check(ui.mail_view == "welcome","Changing city resets mail panel")
	state.city = 6; ui.open("home")
	check(ui.mail_button == null,"Refinery omits mailbox as in original")
	state.city = 1; progress.campaign_stage = 1; progress.mail.available.clear(); progress.mail.outcomes.clear()
	ui.open("home")
	check(ui.mail_button == null and ui.mail_rows.is_empty(),"New game dock has no mailbox button, even with saved prematurely received hint IDs")
	ui.free()
	print("Mailbox: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
