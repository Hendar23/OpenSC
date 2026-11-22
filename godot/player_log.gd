extends Logger

const Storage = preload("res://player_storage.gd")
const ERROR_LABELS := ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"]

static var _started := false

var _file: FileAccess
var _mutex := Mutex.new()

static func start() -> void:
	if _started: return
	var path := Storage.root_path().path_join("OpenSC.log")
	var error := Storage.ensure_parent(path)
	if error != OK:
		push_warning("Could not create player log folder: " + error_string(error))
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not open player log: " + error_string(FileAccess.get_open_error()))
		return

	var logger := new()
	logger._file = file
	logger._write("OpenSC %s | Godot %s | %s | %s | %s" % [
		ProjectSettings.get_setting("application/config/version"),
		Engine.get_version_info().get("string", ""),
		OS.get_name(), RenderingServer.get_current_rendering_method(),
		RenderingServer.get_video_adapter_name(),
	])
	OS.add_logger(logger)
	_started = true

func _log_message(message: String, error: bool) -> void:
	_write(("STDERR: " if error else "") + message)

func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	var details := rationale if not rationale.is_empty() else code
	var message := "%s: %s (%s:%d, %s)" % [ERROR_LABELS[error_type], details, file, line, function]
	for backtrace in script_backtraces:
		if not backtrace.is_empty():
			message += "\n" + backtrace.format()
	_write(message)

func _write(message: String) -> void:
	var timestamp := Time.get_datetime_string_from_system(true, true)
	# Godot can send log messages from worker threads.
	_mutex.lock()
	_file.store_line("[%s UTC] %s" % [timestamp, message.trim_suffix("\n")])
	_file.flush()
	_mutex.unlock()
