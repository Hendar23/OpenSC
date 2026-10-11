extends Node

const Storage = preload("res://player_storage.gd")
const BUS := "Effects"
const MAX_VOLUME := 200.0
var remember_preferences := true
var settings_path := ""
var volume := 100.0
var scope: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if settings_path.is_empty(): settings_path = Storage.preferences_path()
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index,BUS)
		AudioServer.set_bus_send(index,"Master")
	scope = get_parent().get_parent()
	get_tree().node_added.connect(_route)
	_scan(scope)
	var config := ConfigFile.new()
	if remember_preferences and config.load(settings_path) == OK:
		volume = clampf(float(config.get_value("audio","effects_volume",100.0)),0.0,MAX_VOLUME)
	_apply()

func _scan(node: Node) -> void:
	_route(node)
	for child in node.get_children(): _scan(child)

func _route(node: Node) -> void:
	# All ordinary game audio is effects. Explicit buses, including future Music,
	# keep their own routing. This also covers sounds created later by mods.
	if scope != node and not scope.is_ancestor_of(node): return
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		if node.bus == &"Master": node.bus = BUS

func set_volume(value: float) -> Error:
	volume = clampf(value,0.0,MAX_VOLUME)
	_apply()
	if not remember_preferences: return OK
	var config := ConfigFile.new()
	var result := config.load(settings_path)
	if result != OK and result != ERR_FILE_NOT_FOUND: return result
	config.set_value("audio","effects_volume",volume)
	result = Storage.ensure_parent(settings_path)
	return config.save(settings_path) if result == OK else result

func _apply() -> void:
	var index := AudioServer.get_bus_index(BUS)
	AudioServer.set_bus_mute(index,volume <= 0.0)
	AudioServer.set_bus_volume_db(index,linear_to_db(maxf(volume,0.001) / 100.0))
