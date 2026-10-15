extends Control
## One bottom-aligned radio stack, with an active interaction pinned below history.
const MAX_MESSAGES := 4
const LIFETIME := 18.0
const Portrait = preload("res://radio_portrait.gd")
var entries: Array[Dictionary] = []
var prompt: Dictionary = {}

func clear() -> void:
	for entry in entries: entry.row.free()
	entries.clear()
	if not prompt.is_empty(): prompt.row.free()
	prompt = {}

func push_message(message: Dictionary, noise: Array[Texture2D] = []) -> void:
	if str(message.get("text","")).is_empty(): return
	var speaker := str(message.get("speaker",""))
	if not speaker.is_empty():
		if not prompt.is_empty() and str(prompt.message.get("speaker","")) == speaker:
			_replace_entry(prompt,message,noise); return
		for entry in entries:
			if str(entry.message.get("speaker","")) == speaker:
				_replace_entry(entry,message,noise); return
	var key := str(message.get("key",""))
	if not key.is_empty():
		for entry in entries:
			if not entry.closing and str(entry.message.get("key","")) == key: return
	entries.append(_create_entry(message,noise))
	_limit_history()

func set_prompt(message: Dictionary, noise: Array[Texture2D] = []) -> void:
	if not prompt.is_empty() and str(message.get("text","")) == str(prompt.message.text) and message.get("portrait") == prompt.message.get("portrait"): return
	var speaker := str(message.get("speaker",""))
	if not prompt.is_empty() and not speaker.is_empty() and str(prompt.message.get("speaker","")) == speaker:
		_replace_entry(prompt,message,noise); return
	if not prompt.is_empty():
		_begin_exit(prompt); entries.append(prompt); prompt = {}
	if not speaker.is_empty():
		for index in range(entries.size()):
			if str(entries[index].message.get("speaker","")) == speaker:
				prompt = entries[index]; entries.remove_at(index)
				_replace_entry(prompt,message,noise); _limit_history(); return
	if not str(message.get("text","")).is_empty(): prompt = _create_entry(message,noise)
	_limit_history()

func _replace_entry(entry: Dictionary, message: Dictionary, noise: Array[Texture2D]) -> void:
	if entry.closing: entry.portrait.reset_signal()
	entry.message = message.duplicate(); entry.noise = noise
	entry.age = 0.0; entry.closing = false; entry.exit_age = 0.0
	entry.label.text = str(message.text); entry.row.reset_size()
	entry.portrait.update_signal(message.get("portrait"),message.get("distorted_portrait"),noise,0)

func _create_entry(message: Dictionary, noise: Array[Texture2D]) -> Dictionary:
	var text := str(message.get("text",""))
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
	return {"row":row,"portrait":portrait,"label":label,"message":message.duplicate(),"noise":noise,"age":0.0,"closing":false,"exit_age":0.0}

func _begin_exit(entry: Dictionary) -> void:
	if entry.closing: return
	entry.closing = true; entry.exit_age = 0.0
	entry.portrait.update_signal(null,null,entry.noise,0)

func _limit_history() -> void:
	var active := 0 if prompt.is_empty() else 1
	for index in range(entries.size() - 1,-1,-1):
		if entries[index].closing: continue
		active += 1
		if active > MAX_MESSAGES: _begin_exit(entries[index])
	# Preserve the static outro during ordinary replacement, bound extreme bursts.
	while entries.size() > MAX_MESSAGES + 2: entries.pop_front().row.free()

func _advance_entry(entry: Dictionary, delta: float, pinned: bool = false) -> void:
	if entry.closing:
		entry.exit_age += delta
		entry.portrait.update_signal(null,null,entry.noise,delta)
	else:
		entry.age += delta
		entry.portrait.update_signal(entry.message.get("portrait"),entry.message.get("distorted_portrait"),entry.noise,delta)
		if not pinned and entry.age >= LIFETIME: _begin_exit(entry)

func _place(entry: Dictionary, bottom: float, delta: float) -> float:
	bottom -= entry.row.size.y
	entry.row.position.y = lerpf(entry.row.position.y,bottom,1 - exp(-12 * delta))
	return bottom - 6

func _process(delta: float) -> void:
	for entry in entries: _advance_entry(entry,maxf(0,delta))
	for index in range(entries.size() - 1,-1,-1):
		if entries[index].closing and entries[index].exit_age >= Portrait.OUTRO_SECONDS:
			entries[index].row.free(); entries.remove_at(index)
	var bottom := size.y
	if not prompt.is_empty():
		_advance_entry(prompt,maxf(0,delta),true)
		bottom = _place(prompt,bottom,delta)
	for index in range(entries.size() - 1,-1,-1): bottom = _place(entries[index],bottom,delta)
