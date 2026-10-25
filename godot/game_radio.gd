extends RefCounted
## Radio HUD messages, greetings, and bounty announcements.

var game: Node3D

func _init(context: Node3D) -> void:
	game = context


func _build_radio_feed() -> void:
	var hud := CanvasLayer.new()
	hud.layer = 2
	game.add_child(hud)
	game.docked_screen = ColorRect.new()
	game.docked_screen.color = Color(0.02, 0.055, 0.075, 1.0)
	game.docked_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.docked_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.docked_screen.visible = false
	hud.add_child(game.docked_screen)
	game.docked_label = Label.new()
	game.docked_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.docked_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game.docked_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game.docked_label.add_theme_font_size_override("font_size", 28)
	game.docked_screen.add_child(game.docked_label)
	game.radio_feed = preload("res://radio_feed.gd").new()
	game.radio_feed.name = "RadioFeed"; hud.add_child(game.radio_feed)
	game.radio_feed.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	game.radio_feed.offset_left = 20; game.radio_feed.offset_right = 556
	game.radio_feed.offset_top = -340; game.radio_feed.offset_bottom = -20
	game.radio_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.radio_message_audio = preload("res://radio_message_audio.gd").new()
	game.radio_message_audio.name = "RadioMessageAudio"; game.add_child(game.radio_message_audio)


func _radio_audio_allowed() -> bool:
	return not game.world_loading and not game.loading_save and (game.loading_canvas == null or not game.loading_canvas.visible)

func _update_radio_messages(delta: float) -> void:
	if game.radio_feed == null or not _radio_audio_allowed(): return
	if game.docking.greeting_remaining > 0 and not game.docking.greeting_text.is_empty():
		if game.radio_greeting != game.docking.greeting_text:
			game.radio_greeting = game.docking.greeting_text
			var relay: Dictionary = game.docking.greeting_port
			game.radio_feed.push_message({"text":game.radio_greeting,"speaker":"relay/" + str(relay.get("name","")),"key":"greeting/" + str(relay.get("name","")),"portrait":relay.get("greeting_portrait"),"distorted_portrait":relay.get("greeting_distorted_portrait")},game.docking.radio_static)
	else: game.radio_greeting = ""
	var text: String = game.docking.message
	if game.docking.greeting_remaining > 0 and text == game.docking.greeting_text: text = ""
	var rov_prompt: bool = game._rov_prompt_active()
	var delivery: bool = not rov_prompt and game._delivery_prompt_active()
	if delivery: text = "CITY DROP POINT : Do you want attached object to be automatically retrieved? (Y/N)"
	var pinned: bool = rov_prompt or delivery or (game.docking.stage == game.docking.Stage.IDLE and not game.docking.nearby.is_empty())
	var transmission := {"speaker":"dock/" + str(game.docking._portrait_port().get("name","")),"text":text,"portrait":game.docking.portrait_texture(),"distorted_portrait":game.docking.distorted_portrait_texture()}
	if rov_prompt:
		transmission = game.equipment.support_tools.rover.transmission("rover1"); text = str(transmission.get("text",""))
	game.radio_feed.set_prompt(transmission if pinned else {},game.docking.radio_static)
	if not pinned and not text.is_empty() and text != game.radio_status: game.radio_feed.push_message(transmission,game.docking.radio_static)
	game.radio_status = text
	game._age_radio(delta)
	if game.docking.stage == game.docking.Stage.IDLE and game.docking.nearby.is_empty() and not game._delivery_prompt_active() and not rov_prompt:
		if game.bounty_remaining <= 0 and not game.bounty_radio_queue.is_empty():
			game.bounty_port = game.bounty_radio_queue.pop_front(); game.bounty_remaining = 7.0
			if game.bounty_port.get("voice") != null and not game.bounty_port.get("voice_played",false):
				var voice := AudioStreamPlayer.new(); voice.stream = game.bounty_port.voice; voice.volume_db = preload("res://docking_radio.gd").SPEECH_VOLUME_DB; game.add_child(voice)
				voice.finished.connect(voice.queue_free); voice.play()

func _age_radio(delta: float) -> void:
	# A dock prompt can hide a message, but must not preserve an old bounty
	# indefinitely and announce it beside a later, unrelated pirate death.
	game.bounty_remaining = maxf(0,game.bounty_remaining - maxf(0,delta))
	for entry in game.bounty_radio_queue:
		if entry.has("ttl"): entry.ttl -= maxf(0,delta)
	game.bounty_radio_queue = game.bounty_radio_queue.filter(func(entry: Dictionary) -> bool: return not entry.has("ttl") or float(entry.ttl) > 0)

func _pirate_bounty(point: Vector3) -> void:
	var nearest: Dictionary = {}
	var distance := INF
	for port in game.docking.ports:
		var candidate: float = point.distance_squared_to(port.node.global_position)
		if candidate < distance: distance = candidate; nearest = port
	if nearest.is_empty(): return
	game.player_progress.status.credits += 1000
	var announcement := nearest.duplicate()
	announcement.text = "%s: CITY RELAY BEACON : Thank you for your assistance. 1000 credit bounty paid." % nearest.name
	announcement.speaker = "relay/" + str(nearest.name)
	announcement.portrait = nearest.get("greeting_portrait",nearest.portrait)
	announcement.distorted_portrait = nearest.get("greeting_distorted_portrait",nearest.distorted_portrait)
	announcement.ttl = 12.0
	game.bounty_radio_queue.append(announcement)
	if game.radio_feed != null: game.radio_feed.push_message(announcement,game.docking.radio_static)
	if game.dock_interface_active: game.dock_interface.rebuild()
