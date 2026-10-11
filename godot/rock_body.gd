extends "res://salvage_body.gd"

func setup(definition: Dictionary, visual: Node3D, fragment: int, water: float, running: bool) -> void:
	super.setup(definition,visual,fragment,water,running)
	# Reuse solid convex collision, underwater drag, towing and save state.
	# Large original rocks are fixed; the other two can be pushed or grappled.
	freeze = not running or bool(stats.get("immovable",false))
	if bool(stats.get("immovable",false)):
		set_meta("metal_tow_target",false)
		set_meta("grapple_tow_target",false)
