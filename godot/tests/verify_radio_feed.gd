extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	preload("res://player_storage.gd").root_override = "res://tests/cache-mission-fixtures"
	root.size = Vector2i(1280,720)
	var background := ColorRect.new(); background.color = Color(0.02,0.13,0.18)
	background.size = Vector2(1280,720); root.add_child(background)
	var feed := preload("res://radio_feed.gd").new(); root.add_child(feed)
	feed.position = Vector2(20,340); feed.size = Vector2(536,280); feed.set_process(false)
	var radio := preload("res://docking_radio.gd")
	var folder := ProjectSettings.globalize_path("res://../Original Sub Culture")
	var portrait := radio.speaker_portrait(folder,"PIR")
	feed.push_message({"text":""})
	check(feed.entries.is_empty(),"Empty transmission cannot create a phantom message")
	for index in range(5):
		feed.push_message({"text":"Pirate %d: Hey! Where are you going?" % index,"portrait":portrait})
	check(feed.entries.size() == 4 and feed.entries[0].message.text.begins_with("Pirate 1"),"History is bounded and discards oldest first")
	await process_frame; await process_frame
	feed._process(1)
	check(feed.entries[0].row.position.y < feed.entries[-1].row.position.y,"Old messages move above new messages")
	check(feed.entries[-1].portrait.custom_minimum_size == Vector2(40,50),"History portraits use compact dimensions")
	feed.clear()
	feed.push_message({"text":"PIRATE SUB: Hey! Where are you going?","portrait":portrait})
	feed._process(8)
	feed.push_message({"text":"SHIP COMPUTER: Take the raw thorium to the Refinery for processing.","portrait":radio.speaker_portrait(folder,"SHIP")})
	feed.push_message({"text":"Touka Reef: Thank you for your assistance. 1000 credit bounty paid.","portrait":radio.portrait(folder,1)})
	await process_frame; await process_frame
	feed._process(1)
	check(feed.entries.size() == 3,"New arrivals preserve older readable transmissions")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/cache-mission-fixtures/radio-feed.png")
	feed._process(10)
	check(feed.entries.size() == 2,"Old message expires without removing newer messages")
	feed.clear(); check(feed.entries.is_empty() and feed.get_child_count() == 0,"Session reset clears history and portraits")
	for path in ["res://radio_feed.gd","res://tests/verify_radio_feed.gd"]:
		if not FileAccess.file_exists(path + ".uid"):
			var file := FileAccess.open(path + ".uid",FileAccess.WRITE)
			file.store_string(ResourceUID.id_to_text(ResourceUID.create_id()) + "\n")
	print("Radio feed: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
