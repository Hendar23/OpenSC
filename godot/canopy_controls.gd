extends ScrollContainer
const Cockpit = preload("res://first_person_cockpit.gd")
var game: Node
var canopy: Node
var sliders := {}

func _ready() -> void:
	name = "Mods"; process_mode = Node.PROCESS_MODE_ALWAYS
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

func _process(_delta: float) -> void:
	var current: Node = game.first_person_cockpit if is_instance_valid(game.first_person_cockpit) and game.first_person_cockpit.model != null else null
	var tabs := get_parent() as TabContainer
	tabs.set_tab_hidden(get_index(),current == null)
	if current == canopy: return
	canopy = current; sliders.clear()
	for child in get_children(): child.queue_free()
	if canopy == null: return
	var content := VBoxContainer.new(); content.size_flags_horizontal = Control.SIZE_EXPAND_FILL; content.add_theme_constant_override("separation",10); add_child(content)
	var heading := Label.new(); heading.text = "Glass canopy"; content.add_child(heading)
	for row in Cockpit.CONTROLS:
		var key: String = row[0]; var caption: String = row[1]
		var label := Label.new(); content.add_child(label)
		var slider := HSlider.new(); slider.name = key; slider.min_value = row[2]; slider.max_value = row[3]; slider.step = row[4]
		slider.scrollable = false; slider.focus_mode = Control.FOCUS_NONE; slider.value = canopy.settings[key]; content.add_child(slider); sliders[key] = slider
		label.text = "%s: %s" % [caption,str(slider.value)]
		slider.value_changed.connect(func(value: float) -> void:
			if is_instance_valid(canopy): canopy.set_setting(key,value)
			label.text = "%s: %s" % [caption,str(value)])
		slider.drag_ended.connect(func(_changed: bool) -> void:
			if is_instance_valid(canopy):
				var result: Error = canopy.persist_settings()
				if result != OK: heading.text = "Could not save canopy settings: " + error_string(result))
