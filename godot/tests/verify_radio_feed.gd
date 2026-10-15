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
	feed.position = Vector2(20,380); feed.size = Vector2(536,320); feed.set_process(false)
	var radio := preload("res://docking_radio.gd")
	var folder := ProjectSettings.globalize_path("res://../Original Sub Culture")
	var portrait := radio.speaker_portrait(folder,"PIR")
	feed.push_message({"text":""})
	check(feed.entries.is_empty(),"Empty transmission cannot create a phantom message")
	for index in range(5):
		feed.push_message({"text":"Pirate %d: Hey! Where are you going?" % index,"portrait":portrait})
	check(feed.entries.filter(func(e: Dictionary) -> bool: return not e.closing).size() == 4 and feed.entries[0].closing,"Overflow retires oldest message through static")
	feed._process(0.3)
	await process_frame; await process_frame
	feed._process(1)
	check(feed.entries[0].row.position.y < feed.entries[-1].row.position.y,"Old messages move above new messages")
	check(feed.entries[-1].portrait.custom_minimum_size == Vector2(40,50),"History portraits use compact dimensions")
	feed.clear()
	feed.push_message({"text":"CITY RELAY BEACON : Welcome To Bohine City TOUKA REEF.","portrait":radio.speaker_portrait(folder,"touka")})
	feed._process(8)
	feed.push_message({"text":"SHIP COMPUTER: Take the raw thorium to the Refinery for processing.","portrait":radio.speaker_portrait(folder,"SHIP")})
	feed.push_message({"text":"Touka Reef: Thank you for your assistance. 1000 credit bounty paid.","portrait":radio.portrait(folder,1)})
	await process_frame; await process_frame
	feed._process(1)
	check(feed.entries.size() == 3,"New arrivals preserve older readable transmissions")
	if "--capture" in OS.get_cmdline_user_args():
		feed.set_prompt({"text":"Touka Reef: CITY DOCKING PAD : Do you want to dock? (Y/N)","portrait":radio.portrait(folder,1)},radio.static_frames(folder))
		await process_frame; await process_frame
		feed._process(1)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/cache-mission-fixtures/radio-feed.png")
	if not feed.prompt.is_empty():
		feed.prompt.row.free(); feed.prompt = {}
	feed._process(10)
	check(feed.entries[0].closing and feed.entries[0].portrait.transition == "outro","Expired portrait begins static signal loss")
	check(feed.entries[0].row.modulate.a == 1.0,"Message background and text do not fade")
	feed._process(0.3)
	check(feed.entries.size() == 2,"Old message exits after static without removing newer messages")
	feed.clear()
	var noise := radio.static_frames(folder)
	feed.set_prompt({"text":"Touka Reef: Do you want to dock? (Y/N)","portrait":radio.portrait(folder,1)},noise)
	var pinned: Dictionary = feed.prompt
	feed.push_message({"text":"New pirate transmission","portrait":portrait},noise)
	await process_frame; await process_frame
	feed._process(20)
	check(feed.prompt == pinned and not pinned.closing,"Active Y/N prompt stays alive beyond normal lifetime")
	check(pinned.row.position.y > feed.entries[-1].row.position.y,"Pinned prompt stays below new incoming transmissions")
	check(pinned.row.get_theme_stylebox("panel") is StyleBoxFlat,"Prompt shares the dark message background")
	feed.set_prompt({})
	check(feed.prompt.is_empty() and pinned.portrait.transition == "outro","Dismissed interaction begins static outro")
	feed._process(0.1)
	check(pinned.portrait.texture in noise and pinned.row.modulate.a == 1.0,"Outgoing card keeps background while portrait displays original static")
	feed._process(0.2)
	check(not is_instance_valid(pinned.row),"Prompt card disappears after static outro")
	feed.push_message({"text":"Relay greeting","key":"greeting/touka","portrait":portrait})
	feed.push_message({"text":"Relay greeting","key":"greeting/touka","portrait":portrait})
	check(feed.entries.size() == 1,"Repeated city greeting cannot duplicate an existing card")
	feed.clear(); check(feed.entries.is_empty() and feed.get_child_count() == 0,"Session reset clears history and portraits")
	feed.push_message({"speaker":"dock/1","text":"Approach too fast","portrait":portrait})
	var original: Dictionary = feed.entries.back()
	feed.push_message({"speaker":"ship","text":"Other speaker","portrait":portrait})
	feed.push_message({"speaker":"dock/1","text":"Do you want to dock?","portrait":portrait})
	check(feed.entries.size() == 2 and feed.entries[0].row == original.row and original.label.text == "Do you want to dock?","Same speaker replaces text in place without reordering other cards")
	feed.set_prompt({"speaker":"dock/1","text":"Dock? (Y/N)","portrait":portrait})
	check(feed.entries.size() == 1 and feed.prompt.row == original.row,"Existing dock card becomes pinned without a duplicate")
	feed.set_prompt({"speaker":"dock/1","text":"Dock currently in use","portrait":portrait})
	check(feed.entries.size() == 1 and feed.prompt.row == original.row,"Pinned speaker updates reuse the same card")
	feed.set_prompt({})
	feed.push_message({"speaker":"dock/1","text":"Automatic docking in progress","portrait":portrait})
	check(feed.entries.size() == 2 and original.row == feed.entries[-1].row and not original.closing,"Automatic docking replaces the retiring question card")
	feed.clear()
	for path in ["res://radio_feed.gd","res://tests/verify_radio_feed.gd"]:
		if not FileAccess.file_exists(path + ".uid"):
			var file := FileAccess.open(path + ".uid",FileAccess.WRITE)
			file.store_string(ResourceUID.id_to_text(ResourceUID.create_id()) + "\n")
	print("Radio feed: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
