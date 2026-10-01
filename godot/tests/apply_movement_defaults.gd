extends SceneTree
const Movement = preload("res://movement_model.gd")

func _initialize() -> void:
	var movement := Movement.new()
	movement.load_settings(true)
	var saved := ConfigFile.new()
	var result := saved.load("user://submarine_tuning.cfg")
	var matches := result == OK
	for key in movement.defaults:
		matches = matches and is_equal_approx(float(saved.get_value("movement", key, -1.0)), float(movement.defaults[key]))
	print("Updated movement defaults saved: ", matches)
	print("Applied settings: ", movement.settings)
	quit(0 if matches else 1)
