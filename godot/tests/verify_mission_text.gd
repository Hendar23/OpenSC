extends "res://tests/test_scene_tree.gd"
const Runtime = preload("res://mission_runtime.gd")
var checks := 0
var failures := 0
class Context extends Node:
	var gameplay_catalogue := {}
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-text-fixtures"
	storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	call_deferred("run")
func run() -> void:
	preload("res://input_bindings.gd").install()
	check(Runtime._flow_text("Title\r\n\r\nSender line\r\nwrapped here.\r\n<p> Second line. <p> <p> Paragraph\r\ncontinues here.",true) == "Title\n\nSender line wrapped here.\nSecond line.\n\nParagraph continues here.","Soft source wrapping flows while title, explicit line breaks and paragraph spacing survive")
	check(Runtime._flow_text("<p>   <p> Text  with\tspaces@\nwrapped.") == "Text with spaces, wrapped.","Formatting whitespace and original comma escape normalize")
	var folder := ProjectSettings.globalize_path("res://../Original Sub Culture")
	var context := Context.new(); context.gameplay_catalogue = preload("res://original_game_data.gd").load_catalogue(folder,false)
	var runtime := Runtime.new(); runtime.game = context
	for id in ["tradetrad","tradetrad2","tradetech","tradetech2","stranded","spytrad","spytrad2","breakout","breakout2","fishing","bigherd"]:
		var text := runtime.text(id)
		check(text.get_slice("\n",0) == str(context.gameplay_catalogue.tables.mission_text.records[id].text).get_slice("\n",0).strip_edges(),"Mission title remains separate: " + id)
		check(not text.contains("<p>") and not text.contains("#response") and not text.contains("#bulletin"),"Mission formatting and following source sections stay hidden: " + id)
	var briefing := runtime.text("breakout")
	check(briefing.contains("background. Three more Procha"),"Prisoner briefing no longer has the mid-sentence Three/more break")
	check(briefing.contains("Group.\nAgent D Velcova") and briefing.contains("204:\n\nThe CIC"),"Sender line and paragraph boundaries match the original control markers")
	check(runtime.text("breakout",1).contains("Your success is our gain."),"Debriefs also flow across source column wraps")
	check(runtime.welcome(2).contains("\n\n") and not runtime.welcome(2).contains("<p>"),"Mission welcome text keeps intentional paragraphs")
	var ui := preload("res://dock_interface.gd").new(); root.add_child(ui)
	var picture := "MISSSCRE/" + str(context.gameplay_catalogue.tables.mission_availability.records.breakout.picture).to_upper() + ".BMP"
	var state := {"race":2,"city":"Velcova Station","status":{},"missions":{"id":"breakout","available":true,"title":"Save Procha Prisoners","briefing":briefing,"picture":picture,"welcome":runtime.welcome(2)}}
	ui.setup(folder,func() -> Dictionary: return state); ui.open("missions"); ui.mission_selection = "breakout"; ui.rebuild()
	if DisplayServer.get_name() != "headless":
		for frame in range(8): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/stage-two-mission-text.png")
	ui.queue_free(); context.free(); runtime.free(); await process_frame
	print("Mission text: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
