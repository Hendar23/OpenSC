extends Window

signal applied
const Mods = preload("res://mod_registry.gd")
var persist_preferences := true
var rows: VBoxContainer
var info: Label
var choices := {}
var pending_order: Array[String] = []
var pending_enabled: Array[String] = []

func _ready() -> void:
	title = "Mods"
	size = Vector2i(850, 600)
	min_size = Vector2i(650, 450)
	exclusive = true
	close_requested.connect(hide)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = "Enable mods · Later entries take priority"
	heading.add_theme_font_size_override("font_size", 20)
	column.add_child(heading)
	var hint := Label.new()
	hint.text = "Put a mod folder containing mod.json into Mods. Apply reloads the world."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	var refresh := Button.new()
	refresh.text = "Refresh installed mods"
	refresh.pressed.connect(func() -> void: Mods.refresh(); open())
	column.add_child(refresh)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.y = 70
	column.add_child(info)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	var apply := Button.new()
	apply.text = "Apply and reload"
	apply.pressed.connect(_apply)
	buttons.add_child(apply)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(hide)
	buttons.add_child(cancel)
	visible = false

func open() -> void:
	Mods.ensure(persist_preferences)
	pending_order = Mods.order.duplicate()
	pending_enabled = Mods.enabled.duplicate()
	_build_rows()
	popup_centered()

func _build_rows() -> void:
	for child in rows.get_children(): child.free()
	choices.clear()
	for id in pending_order:
		var pack := {}
		for candidate in Mods.packs:
			if str(candidate.id) == id: pack = candidate; break
		if pack.is_empty(): continue
		var item := VBoxContainer.new()
		rows.add_child(item)
		var line := HBoxContainer.new()
		item.add_child(line)
		var enabled := CheckBox.new()
		enabled.text = "%s · %s" % [pack.name, pack.version]
		enabled.disabled = not pack.valid
		enabled.button_pressed = id in pending_enabled and pack.valid
		enabled.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		enabled.toggled.connect(func(on: bool) -> void:
			if on and id not in pending_enabled: pending_enabled.append(id)
			elif not on: pending_enabled.erase(id)
			_update_info()
		)
		line.add_child(enabled)
		choices[id] = enabled
		for direction in [-1, 1]:
			var move := Button.new()
			move.text = "Earlier" if direction == -1 else "Later"
			move.pressed.connect(func() -> void:
				var index := pending_order.find(id)
				var target := clampi(index + direction, 0, pending_order.size() - 1)
				pending_order.remove_at(index)
				pending_order.insert(target, id)
				_build_rows()
			)
			line.add_child(move)
		var description := Label.new()
		description.text = str(pack.description)
		if not pack.errors.is_empty(): description.text += "\n" + "\n".join(pack.errors)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item.add_child(description)
	_update_info()

func _update_info() -> void:
	info.text = "No mods installed." if Mods.packs.is_empty() else "Original assets remain the fallback. Disabling all mods restores the base game."
	var notes: Array[String] = []
	var sources := {}
	for id in pending_order:
		for pack in Mods.packs:
			if str(pack.id) != id or not pack.valid or id not in pending_enabled: continue
			var keys: Array = pack.assets.keys()
			for key in pack.movement: keys.append("movement." + str(key))
			for key in keys:
				if sources.has(key): notes.append("%s: %s overrides %s" % [key, pack.name, sources[key]])
				sources[key] = pack.name
	notes.append_array(Mods.runtime_warnings)
	if not notes.is_empty(): info.text += "\n" + "\n".join(notes.slice(0, 5))
	if notes.size() > 5: info.text += "\n%d more notes (hover to read)." % (notes.size() - 5)
	info.tooltip_text = "\n".join(notes)

func _apply() -> void:
	var result := Mods.apply(pending_enabled, pending_order, persist_preferences)
	if result != OK:
		info.text = "Could not save mod selection: " + error_string(result)
		return
	hide()
	applied.emit()
