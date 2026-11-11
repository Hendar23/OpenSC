extends Node
## Remains with the battleship if the mission ends before its guns are lost.
signal destroyed
var guns: Array[Node3D] = []
var traffic: Node
var runtime: Node

func _ready() -> void:
	name = "FilterBattleshipDestruction"

func _physics_process(_delta: float) -> void:
	if guns.size() != 2 or not guns.all(func(gun: Node3D) -> bool: return gun.dead): return
	set_physics_process(false)
	var boss := get_parent() as Node3D
	runtime.retained_props.erase(boss)
	preload("res://falling_submarine.gd").launch_boss(traffic,boss)
	destroyed.emit()
	queue_free()
