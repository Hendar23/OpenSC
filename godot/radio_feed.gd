extends Control
## Compact recent transmissions, oldest at the top and newest at the bottom.
const MAX_MESSAGES := 4
const LIFETIME := 18.0
var entries: Array[Dictionary] = []

func clear() -> void:
	for entry in entries: entry.row.free()
	entries.clear()

func push_message(message: Dictionary, noise: Array[Texture2D] = []) -> void:
	var text := str(message.get("text",""))
	if text.is_empty(): return
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new(); style.bg_color = Color(0.005,0.025,0.035,0.72)
	style.set_corner_radius_all(4); style.content_margin_left = 8; style.content_margin_right = 8
	style.content_margin_top = 6; style.content_margin_bottom = 6
	row.add_theme_stylebox_override("panel",style)
	add_child(row)
	var content := HBoxContainer.new(); content.add_theme_constant_override("separation",10)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE; row.add_child(content)
	var portrait := preload("res://radio_portrait.gd").new()
	portrait.custom_minimum_size = Vector2(40,50)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE; content.add_child(portrait)
	portrait.update_signal(message.get("portrait"),message.get("distorted_portrait"),noise,0)
	var label := Label.new(); label.text = text; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 470; label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; label.add_theme_font_size_override("font_size",14)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE; content.add_child(label)
	row.size.x = 536; row.position = Vector2(0,size.y + 8)
	entries.append({"row":row,"portrait":portrait,"message":message.duplicate(),"noise":noise,"age":0.0})
	while entries.size() > MAX_MESSAGES: entries.pop_front().row.free()

func _process(delta: float) -> void:
	for entry in entries:
		entry.age += delta
		entry.portrait.update_signal(entry.message.get("portrait"),entry.message.get("distorted_portrait"),entry.noise,delta)
	for index in range(entries.size() - 1,-1,-1):
		if entries[index].age >= LIFETIME:
			entries[index].row.free(); entries.remove_at(index)
	var bottom := size.y
	for index in range(entries.size() - 1,-1,-1):
		var entry := entries[index]
		bottom -= entry.row.size.y
		entry.row.position.y = lerpf(entry.row.position.y,bottom,1 - exp(-12 * delta))
		entry.row.modulate.a = clampf((LIFETIME - float(entry.age)) / 2.0,0,1)
		bottom -= 6
