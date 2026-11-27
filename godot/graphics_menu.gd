extends CanvasLayer

const Bindings = preload("res://input_bindings.gd")
const Graphics = preload("res://player_graphics.gd")
const DISPLAY_ROWS := [
	["display_mode","Display mode"], ["resolution","Resolution"], ["limit_resolutions","Limit to display"],
	["vsync","VSync"], ["frame_limit","Frame-rate limit"], ["brightness","Brightness"], ["contrast","Contrast"],
	["fmvs_enabled","Play FMVs"], ["fmv_size","FMV size"],
]
const GRAPHICS_ROWS := [
	["anti_aliasing","Anti-aliasing"], ["shadows","Shadow quality"], ["fog_distance","Fog distance"],
	["reflective_canopies","Reflective canopies"], ["sun_shafts_enabled","Sun shafts"], ["lens_flares_enabled","Lens flares"],
	["classic_explosions","Classic explosions"], ["bubble_limit","Maximum bubbles"], ["wildlife_limit","Active wildlife"],
]
const DIFFICULTY_ROWS := [
	["disable_random_pirates","Disable random pirates"], ["random_pirate_weapons","Random NPC submarine weapons"],
	["zapper_auto_aim","Zapper auto aim"],
]
const GAMEPLAY_ACTIONS := {
	"fmvs_enabled": &"_toggle_fmvs",
	"sun_shafts_enabled": &"_toggle_sun_shafts",
	"lens_flares_enabled": &"_toggle_lens_flares",
	"classic_explosions": &"_toggle_classic_explosions",
	"bubble_limit": &"_cycle_bubble_limit",
	"wildlife_limit": &"_cycle_wildlife_limit",
	"disable_random_pirates": &"_toggle_random_pirates",
	"random_pirate_weapons": &"_toggle_pirate_weapons",
	"zapper_auto_aim": &"_toggle",
}
signal closed
const ROW_SPACING := 27
const ROW_LEFT := 75
const ROW_WIDTH := 490
const VALUE_WIDTH := 198
var rows := GRAPHICS_ROWS
var graphics: Node
var gameplay: Node
var layout: Control
var controls := {}
var labels := {}
var order: Array[Control] = []
var row_start: int
var status: Label
var back: Button
var normal: StyleBoxFlat
var hover: StyleBoxFlat

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS; layer = 12
	var shade := ColorRect.new(); shade.color = Color.TRANSPARENT
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(shade)
	layout = Control.new(); layout.size = Vector2(640,480); shade.add_child(layout)
	normal = StyleBoxFlat.new(); normal.bg_color = Color(0.01,0.05,0.07,0.82)
	normal.border_color = Color(0.24,0.55,0.6,0.7); normal.set_border_width_all(1); normal.set_corner_radius_all(5)
	hover = normal.duplicate(); hover.bg_color = Color(0.04,0.23,0.28,0.95)
	row_start = roundi((480.0 - rows.size() * ROW_SPACING - 55.0) * 0.5)
	for entry in rows: _add_row(entry[0],entry[1])
	var back_y := row_start + rows.size() * ROW_SPACING + 4
	status = Label.new(); status.position = Vector2(ROW_LEFT,back_y + 28); status.size = Vector2(ROW_WIDTH,23)
	status.add_theme_font_size_override("font_size",12); layout.add_child(status)
	back = _button("Back"); back.position = Vector2(216,back_y); back.size = Vector2(208,28)
	layout.add_child(back); back.pressed.connect(close_menu); order.append(back)
	get_viewport().size_changed.connect(_layout); _layout(); hide()

func _button(text: String) -> Button:
	var button := Button.new(); button.text = text; button.add_theme_font_size_override("font_size",14)
	button.add_theme_stylebox_override("normal",normal)
	for state in ["hover","pressed","focus"]: button.add_theme_stylebox_override(state,hover)
	return button

func _add_row(key: String,title: String) -> void:
	var y := row_start + controls.size() * ROW_SPACING
	var panel := Panel.new(); panel.position = Vector2(ROW_LEFT,y); panel.size = Vector2(ROW_WIDTH,26)
	panel.add_theme_stylebox_override("panel",normal); panel.mouse_filter = Control.MOUSE_FILTER_IGNORE; layout.add_child(panel)
	var label := Label.new(); label.position = Vector2(ROW_LEFT + 10,y); label.size = Vector2(ROW_WIDTH - VALUE_WIDTH - 26,26)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; label.text = title
	label.add_theme_font_size_override("font_size",14); layout.add_child(label); labels[key] = label
	var control: Control
	if key in ["brightness","contrast","fog_distance"]:
		var slider := HSlider.new()
		match key:
			"fog_distance":
				slider.min_value = Graphics.MIN_FOG_DISTANCE
				slider.max_value = Graphics.MAX_FOG_DISTANCE
			"contrast":
				slider.min_value = Graphics.MIN_CONTRAST
				slider.max_value = Graphics.MAX_CONTRAST
			"brightness":
				slider.min_value = 50.0
				slider.max_value = 150.0
		slider.step = 1; slider.scrollable = false
		slider.value_changed.connect(func(value: float) -> void: _change(key,value))
		control = slider
	else:
		var button := _button(""); button.pressed.connect(func() -> void: _cycle(key,1)); control = button
	control.position = Vector2(ROW_LEFT + ROW_WIDTH - VALUE_WIDTH - 10,y + 2); control.size = Vector2(VALUE_WIDTH,24)
	layout.add_child(control); controls[key] = control; order.append(control)

func _choices(key: String) -> Array:
	match key:
		"display_mode": return [0,1,2]
		"resolution": return graphics.resolutions()
		"fmv_size": return Graphics.FMV_SIZES
		"vsync","limit_resolutions","reflective_canopies": return [true,false]
		"frame_limit": return graphics.FRAME_LIMITS
		"anti_aliasing", "shadows": return [0,1,2,3]
	return []

func _cycle(key: String,direction: int) -> void:
	if GAMEPLAY_ACTIONS.has(key):
		var action := Callable(gameplay,GAMEPLAY_ACTIONS[key])
		var result: Error = action.call(direction) if key in ["bubble_limit","wildlife_limit"] else action.call()
		_show_save_result(result)
		return
	var values := _choices(key)
	_change(key,values[posmod(values.find(graphics.settings[key]) + direction,values.size())])

func _change(key: String,value: Variant) -> void:
	_show_save_result(graphics.set_value(key,value))

func _show_save_result(result: Error) -> void:
	status.text = "" if result == OK else tr("Could not save settings: %s") % error_string(result)
	_refresh()

func _refresh() -> void:
	for key in controls:
		var value: Variant = gameplay.get(key) if GAMEPLAY_ACTIONS.has(key) else graphics.settings[key]
		if controls[key] is HSlider:
			controls[key].set_value_no_signal(value)
			var title := "Fog distance" if key == "fog_distance" else String(key).capitalize()
			labels[key].text = "%s: %d%%" % [tr(title),roundi(value)]
		else:
			var text := ""
			match key:
				"display_mode": text = ["Fullscreen","Borderless","Windowed"][int(value)]
				"resolution": text = "%d × %d" % [value.x,value.y]
				"fmv_size": text = "Classic size" if value == Graphics.CLASSIC_FMV_SIZE else "%d%%" % value
				"bubble_limit": text = "Unlimited" if value < 0 else "Off" if value == 0 else str(value)
				"wildlife_limit": text = "Unlimited" if value == 0 else str(value)
				"frame_limit": text = "Unlimited" if int(value) == 0 else "%d FPS" % value
				"anti_aliasing": text = ["Off","MSAA 2×","MSAA 4×","MSAA 8×"][int(value)]
				"shadows": text = ["Off","Low","Medium","High"][int(value)]
				_: text = "On" if value else "Off"
			controls[key].text = "‹  %s  ›" % tr(text)

func open_menu() -> void:
	_refresh(); status.text = ""; show(); order[0].grab_focus()

func close_menu() -> void:
	if not visible: return
	hide(); closed.emit()

func _layout() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var factor := minf(viewport.x / 640.0,viewport.y / 480.0)
	layout.scale = Vector2.ONE * factor
	layout.position = (viewport - Vector2(640,480) * factor) * 0.5

func _input(event: InputEvent) -> void:
	if not visible: return
	var focused := get_viewport().gui_get_focus_owner()
	if Bindings.pressed(event,"menu_cancel"):
		close_menu()
	elif Bindings.pressed(event,"menu_up") or Bindings.pressed(event,"menu_down"):
		var step := 1 if Bindings.pressed(event,"menu_down") else -1
		order[posmod(order.find(focused) + step,order.size())].grab_focus()
	elif Bindings.pressed(event,"menu_left") or Bindings.pressed(event,"menu_right"):
		var step := 1 if Bindings.pressed(event,"menu_right") else -1
		if focused is HSlider: focused.value += step
		else:
			for key in controls:
				if controls[key] == focused: _cycle(key,step); break
	elif Bindings.pressed(event,"menu_accept"):
		if focused is Button: focused.pressed.emit()
	else: return
	get_viewport().set_input_as_handled()
