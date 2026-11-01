extends CanvasLayer
## A startup-only check. Network failures deliberately have no player-facing error.
const Versions = preload("res://official_mods.gd")
const Bindings = preload("res://input_bindings.gd")
const RELEASES_URL := "https://api.github.com/repos/Hendar23/OpenSC/releases?per_page=100"
const RELEASE_PAGE := "https://github.com/Hendar23/OpenSC/releases/tag/"
signal decided(download: bool)
var prompt: Control
var download_button: Button
var continue_button: Button
var message: Label
var browser_open: Callable = func(url: String) -> int: return OS.shell_open(url)
var close_game: Callable = func() -> void: get_tree().quit()

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30

static func available(body: String, current: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(body) != OK: return {}
	var releases = parser.data
	if not releases is Array: return {}
	var tag_pattern := RegEx.new()
	tag_pattern.compile("^v?[0-9]+\\.[0-9]+\\.[0-9]+(?:-[A-Za-z0-9.-]+)?$")
	var best := current
	var found := {}
	for release in releases:
		if not release is Dictionary or release.get("draft",true) != false: continue
		var tag = release.get("tag_name",null)
		if not tag is String or tag_pattern.search(tag) == null: continue
		if not Versions.newer(tag,best): continue
		best = tag
		found = {"version":tag.trim_prefix("v"),"url":RELEASE_PAGE + tag.uri_encode()}
	return found

func check_latest(url: String = RELEASES_URL) -> Dictionary:
	var http := HTTPRequest.new()
	# This small metadata response uses non-blocking main-loop polling.
	http.use_threads = false
	http.timeout = 5.0
	http.body_size_limit = 2097152
	add_child(http)
	var error := http.request(url,["Accept: application/vnd.github+json","User-Agent: OpenSC"])
	if error != OK:
		http.queue_free()
		return {}
	var response: Array = await http.request_completed
	http.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200: return {}
	return available(response[3].get_string_from_utf8(),str(ProjectSettings.get_setting("application/config/version","0.0.0")))

func offer(release: Dictionary) -> bool:
	_build_prompt(release.version)
	var download: bool = await decided
	prompt.hide()
	if download and browser_open.call(release.url) == OK:
		close_game.call()
		return true
	return false

func _build_prompt(version: String) -> void:
	prompt = ColorRect.new()
	(prompt as ColorRect).color = Color(0,0,0,0.7)
	add_child(prompt)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var centre := CenterContainer.new()
	prompt.add_child(centre)
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	centre.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_" + side,24)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",20)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = "Update available"
	heading.add_theme_font_size_override("font_size",26)
	column.add_child(heading)
	message = Label.new()
	message.text = "OpenSC Beta v%s is available. Would you like to open the download page?" % version
	message.custom_minimum_size.x = 480
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation",16)
	column.add_child(buttons)
	download_button = Button.new(); download_button.text = "Download update"
	continue_button = Button.new(); continue_button.text = "Continue"
	buttons.add_child(download_button); buttons.add_child(continue_button)
	download_button.pressed.connect(func() -> void: decided.emit(true))
	continue_button.pressed.connect(func() -> void: decided.emit(false))
	continue_button.grab_focus()

func _input(event: InputEvent) -> void:
	if prompt == null or not prompt.visible: return
	if Bindings.pressed(event,"menu_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled(); decided.emit(false)
	elif Bindings.pressed(event,"menu_left") or Bindings.pressed(event,"menu_right") or Bindings.pressed(event,"menu_up") or Bindings.pressed(event,"menu_down"):
		get_viewport().set_input_as_handled()
		if download_button.has_focus(): continue_button.grab_focus()
		else: download_button.grab_focus()
	elif Bindings.pressed(event,"menu_accept"):
		get_viewport().set_input_as_handled()
		decided.emit(download_button.has_focus())
