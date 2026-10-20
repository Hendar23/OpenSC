extends MarginContainer
## Credits and hold contents beside the existing whole-world map.
const Bindings = preload("res://input_bindings.gd")
const GOLD := Color(1,0.8,0.15)
var model: Callable
var map: Control
var panel: PanelContainer
var scroll: ScrollContainer
var credits: Label
var fields := {}
var item_names := {}
var commodity_names := {}
var previous := {}
var elapsed := 0.0
var row: HBoxContainer
var body: VBoxContainer

func setup(player: Node3D, data: RefCounted, catalogue: Dictionary, source: Callable) -> void:
	model = source
	var tables: Dictionary = catalogue.get("tables",{})
	for id in tables.get("equipment_text",{}).get("records",{}):
		item_names[str(id)] = str(tables.equipment_text.records[id].get("name",str(id).capitalize()))
	item_names["deep_sea_lights"] = item_names.get("lights","Deep Sea Lights")
	item_names.merge(preload("res://equipment_shop.gd").TORPEDO_NAMES,true)
	for id in tables.get("commodity_text",{}).get("records",{}):
		commodity_names[str(id).to_lower()] = str(tables.commodity_text.records[id].get("Display name",str(id).capitalize()))
	row = HBoxContainer.new(); add_child(row)
	map = preload("res://hud_display.gd").new()
	map.pilot = player; map.map_data = data; map.screen_only = true; map.full_world = true
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE; row.add_child(map)
	panel = PanelContainer.new(); row.add_child(panel)
	panel.theme = Theme.new(); panel.theme.default_font = ThemeDB.fallback_font
	panel.theme.set_color("font_color","Label",GOLD)
	var style := StyleBoxFlat.new(); style.bg_color = Color(0.015,0.025,0.035)
	style.border_color = Color(0.28,0.24,0.12); style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel",style)
	var column := VBoxContainer.new(); panel.add_child(column)
	credits = _label(""); credits.name = "Credits"; column.add_child(credits)
	scroll = ScrollContainer.new(); scroll.name = "InventoryScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; column.add_child(scroll)
	body = VBoxContainer.new(); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(body)
	var contents := _label(""); contents.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(contents); fields["hold"] = contents
	resized.connect(_resize)
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree(): refresh())
	_resize(); refresh()

func _label(value: String) -> Label:
	var result := Label.new(); result.text = value
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

func _resize() -> void:
	if panel == null: return
	var viewport_size := get_viewport_rect().size
	var factor := minf(viewport_size.x / 640.0,viewport_size.y / 480.0)
	factor = maxf(0.5,factor)
	for side in ["left","right","top","bottom"]: add_theme_constant_override("margin_" + side,int(16 * factor))
	row.add_theme_constant_override("separation",int(16 * factor))
	panel.custom_minimum_size.x = 200 * factor
	panel.theme.default_font_size = maxi(8,roundi(10 * factor))
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel")
	style.content_margin_left = 12 * factor; style.content_margin_right = 12 * factor
	style.content_margin_top = 12 * factor; style.content_margin_bottom = 12 * factor
	credits.add_theme_font_size_override("font_size",maxi(10,roundi(14 * factor)))
	body.add_theme_constant_override("separation",int(5 * factor))

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	elapsed += delta
	if elapsed >= 0.2: elapsed = 0; refresh()

func refresh() -> void:
	if not model.is_valid(): return
	var data: Dictionary = model.call()
	if data == previous: return
	previous = data.duplicate(true)
	credits.text = "Credits: %d" % int(data.get("credits",0))
	var goods := _contents(data.get("cargo",{}),commodity_names)
	var equipment := _contents(data.get("hold",{}),item_names)
	fields.hold.text = "\n".join([goods,equipment]) if not goods.is_empty() and not equipment.is_empty() else goods + equipment
	if fields.hold.text.is_empty(): fields.hold.text = "Empty"

func _contents(items: Dictionary, names: Dictionary) -> String:
	var lines := PackedStringArray()
	var ids := items.keys(); ids.sort()
	for id in ids:
		if int(items[id]) <= 0: continue
		var title := str(names.get(id,str(id).capitalize()))
		lines.append("%s ×%d" % [title,int(items[id])])
	return "\n".join(lines)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or scroll == null: return
	var press := event
	if event is InputEventKey and event.echo:
		press = event.duplicate(); press.echo = false
	var direction := int(Bindings.pressed(press,"menu_down")) - int(Bindings.pressed(press,"menu_up"))
	if direction == 0: return
	scroll.scroll_vertical += direction * maxi(24,roundi(credits.get_theme_font_size("font_size") * 3))
	get_viewport().set_input_as_handled()
