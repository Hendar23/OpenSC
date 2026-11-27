extends SceneTree
const Updates = preload("res://game_updates.gd")
const WindowsUpdate = preload("res://windows_game_update.gd")
const Bindings = preload("res://input_bindings.gd")
var checks := 0
var failures := 0
var server := TCPServer.new()
var peers: Array[StreamPeerTCP] = []
var served: Array[StreamPeerTCP] = []
var reply := ""
var stall := false
var opened := ""
var closed := false
var continued := false

func _initialize() -> void:
	process_frame.connect(_serve)
	call_deferred("_run")
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(description)

func _serve() -> void:
	if server.is_connection_available(): peers.append(server.take_connection())
	for peer in peers:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED: continue
		if peer.get_available_bytes() > 0 and not stall and peer not in served:
			peer.get_data(peer.get_available_bytes())
			peer.put_data(reply.to_utf8_buffer())
			served.append(peer)

func response(body: String, status: int = 200) -> void:
	reply = "HTTP/1.1 %d Test\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [status,body.to_utf8_buffer().size(),body]

func service() -> CanvasLayer:
	var updates := Updates.new()
	updates.browser_open = func(url: String) -> int: opened = url; return OK
	updates.close_game = func() -> void: closed = true
	root.add_child(updates)
	return updates

func offer(updates: CanvasLayer) -> void:
	var exiting: bool = await updates.offer({"version":"1.0.0","url":Updates.RELEASE_PAGE + "v1.0.0"})
	continued = not exiting

func key(code: Key) -> void:
	var event := InputEventKey.new(); event.keycode = code; event.pressed = true
	root.push_input(event,true)
	await process_frame

func pad(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new(); event.button_index = button; event.pressed = true
	root.push_input(event,true)
	await process_frame

func _run() -> void:
	# Keep the HTTP fixture independent of the current project release.
	ProjectSettings.set_setting("application/config/version","0.8.2")
	Bindings.bindings = Bindings.defaults(); Bindings.apply_all()
	root.size = Vector2i(1280,720)
	var releases := JSON.stringify([
		{"draft":false,"tag_name":"v0.8.2"},
		{"draft":true,"tag_name":"v9.0.0"},
		{"draft":false,"tag_name":"clownfish-v9.0"},
		{"draft":false,"tag_name":"v0.8.3"},
		{"draft":false,"tag_name":"v0.8.4-beta.1"}])
	var latest := Updates.available(releases,"0.8.2")
	check(latest.get("version") == "0.8.4-beta.1","Published beta updates count; drafts and unrelated tags are ignored")
	check(latest.get("url") == Updates.RELEASE_PAGE + "v0.8.4-beta.1","Download goes to that exact game release")
	var installer_name := "OpenSC-0.8.4-beta.1-Windows-x64-Setup.exe"
	var installer_url := "https://github.com/Hendar23/OpenSC/releases/download/v0.8.4-beta.1/" + installer_name
	var sha256 := "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
	var published := {"draft":false,"tag_name":"v0.8.4-beta.1","assets":[
		{"name":installer_name,"browser_download_url":"https://example.com/" + installer_name,"state":"uploaded","digest":"sha256:" + sha256},
		{"name":installer_name,"browser_download_url":installer_url,"state":"uploaded","digest":"sha256:" + sha256}]}
	var installer := Updates.available(JSON.stringify([published]),"0.8.2")
	check(installer.get("installer_url") == installer_url and installer.get("installer_sha256") == sha256,
		"Self-update uses the exact pinned GitHub asset and its release digest")
	for invalid_digest in [null, "", "sha256:" + sha256 + "x"]:
		published.assets[1].digest = invalid_digest
		check(not Updates.available(JSON.stringify([published]),"0.8.2").has("installer_url"),
			"An installer without a valid GitHub digest falls back to the release page")
	published.assets.pop_back()
	check(not Updates.available(JSON.stringify([published]),"0.8.2").has("installer_url"),
		"A URL outside the expected release falls back to the release page")
	check(Updates.available(releases,"0.8.4-beta.1").is_empty(),"Equal release never prompts")
	check(Updates.available(releases,"1.0.0").is_empty(),"Older releases never prompt")
	for invalid in ["", "not JSON", "{}", "[null,3,{}]", '[{"draft":false,"tag_name":"https://example.com"}]']:
		check(Updates.available(invalid,"0.8.2").is_empty(),"Malformed metadata silently gives no update")
	var updates := service()
	check(server.listen(0,"127.0.0.1") == OK,"Local HTTP fixture starts")
	var url := "http://127.0.0.1:%d/" % server.get_local_port()
	var fixture_path := "user://update-digest-test-%d.tmp" % OS.get_process_id()
	var fixture_file := FileAccess.open(fixture_path, FileAccess.WRITE)
	fixture_file.store_string("abc")
	fixture_file.close()
	check(WindowsUpdate.matches_digest(fixture_path, sha256), "Matching unsigned download bytes pass the digest check")
	check(not WindowsUpdate.matches_digest(fixture_path, "0".repeat(64)), "Changed download bytes fail the digest check")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path))
	response("abc")
	check(not (await WindowsUpdate.start(updates, {"installer_url":url,"installer_sha256":"0".repeat(64)})),
		"Downloaded installer with the wrong digest is rejected before launch")
	response(releases)
	check(not (await updates.check_latest(url)).is_empty(),"Real HTTP response detects update")
	response("not JSON")
	check((await updates.check_latest(url)).is_empty(),"Malformed HTTP response silently continues")
	response(releases,503)
	check((await updates.check_latest(url)).is_empty(),"HTTP failure silently continues")
	stall = true
	var started := Time.get_ticks_msec()
	check((await updates.check_latest(url)).is_empty(),"Unresponsive server silently continues")
	check(Time.get_ticks_msec()-started >= 4800 and Time.get_ticks_msec()-started < 6500,"Unresponsive check has five-second deadline")
	server.stop()
	for peer in peers: peer.disconnect_from_host()
	check((await updates.check_latest(url)).is_empty(),"Offline connection refusal silently continues")
	updates.queue_free(); await process_frame
	updates = service(); offer(updates); await process_frame
	check(updates.continue_button.has_focus(),"Continue initially selected")
	check(updates.message.text == "OpenSC v1.0.0 is available. Would you like to open the download page?","Update prompt does not assume the offered release is a beta")
	await key(KEY_ESCAPE)
	check(continued and opened.is_empty() and not closed,"Esc continues without browser or quit")
	updates.queue_free(); await process_frame
	continued = false; updates = service(); offer(updates); await process_frame
	await pad(JOY_BUTTON_B)
	check(continued and not closed,"Controller B continues")
	updates.queue_free(); await process_frame
	continued = false; updates = service(); offer(updates); await process_frame
	await key(KEY_LEFT)
	check(updates.download_button.has_focus(),"Keyboard navigation selects Download update")
	await pad(JOY_BUTTON_A)
	check(opened == Updates.RELEASE_PAGE + "v1.0.0" and closed and not continued,"Controller confirmation opens exact release then closes game")
	updates.queue_free(); await process_frame
	closed = false; continued = false; updates = service()
	updates.browser_open = func(_url: String) -> int: return ERR_CANT_OPEN
	offer(updates); await process_frame
	updates.download_button.pressed.emit(); await process_frame
	check(continued and not closed,"Browser launch failure keeps game open and continues loading")
	updates.queue_free(); await process_frame
	updates = service()
	updates._build_prompt("1.0.0", true)
	check(updates.message.text == "OpenSC v1.0.0 is available. Install it and restart the game?", "Installed update explains the restart")
	check(updates.download_button.text == "Install update" and updates.continue_button.text == "Continue", "Installed update uses the approved button labels")
	check(updates.continue_button.has_focus(), "Continue is initially selected for installed updates")
	updates.queue_free(); await process_frame
	print("Game updates: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
