extends SceneTree
const Editor = preload("res://asset_editor.gd")
const Pulse = preload("res://pulse_light.gd")
const Document = preload("res://map_document.gd")
const Mods = preload("res://mod_registry.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _run() -> void:
	Mods.initialize(false)
	var editor := Editor.new(); editor.remember_preferences = false; root.add_child(editor)
	await process_frame
	editor._set_mode(true)
	var map: HBoxContainer = editor.map_editor
	for frame in range(1800):
		if map.loaded: break
		await physics_frame
	check(map.loaded, "World loads")
	if not map.loaded: quit(1); return
	var key := ""
	var count := 0
	for candidate in map.document.entities:
		if map.document.entities[candidate].kind != "light" or map.document.entities[candidate].get("deleted", false): continue
		count += 1; key = candidate
		check(map.world.get_node(NodePath(key)) is Pulse, "Existing light receives pulse, including saved legacy map entries")
	check(count > 0, "Original map lights exist")
	var light: OmniLight3D = map.world.get_node(NodePath(key))
	light.set_process(false); light.phase = 0
	check(Pulse.mode_from({}) == "flashing" and Pulse.mode_from({"pulse_enabled": true}) == "pulsing" and Pulse.mode_from({"pulse_enabled": false}) == "steady", "Default flashes while explicitly saved old styles are preserved")
	light.light_mode = "flashing"; light.flash_on_time = 0.5; light.flash_off_time = 1.0
	for time in [0.0, 0.49, 0.5, 1.49, 1.5, 1.99, 2.0]:
		light.elapsed = time; light.update_pulse()
		var on: bool = fposmod(time, 1.5) < 0.5
		check(is_equal_approx(light.light_energy, light.peak_energy if on else 0.0) and light.flare.visible == on, "Flash cycle switches flare and light fully on/off at %.2f" % time)
	light.light_mode = "pulsing"; light.elapsed = light.pulse_period * 0.25; light.update_pulse()
	check(is_equal_approx(light.light_energy, light.peak_energy), "Pulse reaches peak")
	light.elapsed = light.pulse_period * 0.75; light.update_pulse()
	check(is_equal_approx(light.light_energy, light.peak_energy * light.pulse_minimum), "Pulse reaches minimum smoothly")
	check(light.material.albedo_texture != null and light.material.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED and not light.material.no_depth_test and not light.material.disable_fog, "Original flare faces camera and respects geometry/fog")
	var pixels: Image = light.material.albedo_texture.get_image()
	check(pixels.get_pixel(0, 0).a == 0.0 and pixels.get_pixel(pixels.get_width() - 1, pixels.get_height() - 1).a == 0.0, "Black flare corners stay transparent under fog")
	var soft_pixel := pixels.get_pixel(pixels.get_width() / 2 + 12, pixels.get_height() / 2 + 12)
	check(soft_pixel.a > 0.0 and soft_pixel.a < 1.0 and soft_pixel.r > 0.9, "Soft glow uses feathered alpha without losing brightness")
	var captured := Document.capture(map.world)
	check(captured.entities[key].energy == light.peak_energy, "Saving stores peak energy rather than animated brightness")
	map.category.select(2); map.select(key)
	map.fields.pulse_period.value = 3.7; map.fields.pulse_minimum.value = 35; map.fields.flare_size.value = 5.1
	map.fields.light_mode.select(0); map.apply_properties()
	light = map.world.get_node(NodePath(key))
	check(light.pulse_period == 3.7 and is_equal_approx(light.pulse_minimum, 0.35) and is_equal_approx(light.flare_size, 5.1) and light.light_mode == "steady", "Editor controls apply pulse settings")
	check(is_equal_approx(light.light_energy, light.peak_energy), "Disabled pulse is steady")
	map.fields.light_mode.select(2); map._update_light_fields()
	check(map.fields.flash_on_time.visible and not map.fields.pulse_period.visible, "Flashing selection exposes only relevant timing controls")
	map.fields.flash_on_time.value = 0.3; map.fields.flash_off_time.value = 2.0; map.apply_properties()
	check(light.light_mode == "flashing" and is_equal_approx(light.flash_on_time, 0.3) and is_equal_approx(light.flash_off_time, 2.0), "Editor applies custom flash timing")
	map.duplicate_selection()
	var clone: OmniLight3D = map.world.get_node(NodePath(map.selected))
	check(clone is Pulse and clone.material != light.material, "Duplicated light has independent flare material")
	map.select(key); map.delete_selection(); map.undo()
	check(map.world.get_node(NodePath(key)) is Pulse, "Undo restores a working pulse light")
	map._add_entity("light", "")
	check(map.world.get_node(NodePath(map.selected)) is Pulse, "Added lights support the same effect")
	var data: Variant = JSON.parse_string(JSON.stringify(map.document))
	check(Document.valid(data) and data.entities[key].pulse_period == 3.7, "Pulse settings round trip as map JSON")
	check(data.entities[key].light_mode == "flashing" and is_equal_approx(data.entities[key].flash_on_time, 0.3) and data.entities[key].flash_off_time == 2.0, "Flash settings round trip as map JSON")
	data.entities[key].flash_off_time = 0.0; check(not Document.valid(data), "Zero flash duration rejected")
	data.entities[key].flash_off_time = 2.0
	data.entities[key].light_mode = "invalid"; check(not Document.valid(data), "Unknown light style rejected")
	data.entities[key].light_mode = "flashing"
	data.entities[key].pulse_period = 0.0; check(not Document.valid(data), "Invalid period rejected")
	print("Pulse light verification: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
