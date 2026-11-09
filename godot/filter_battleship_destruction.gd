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
	for body in boss.find_children("*","CollisionObject3D",true,false):
		body.set_deferred("collision_layer",0)
		body.set_deferred("collision_mask",0)
	var effect := preload("res://base_destruction.gd").new()
	boss.get_parent().add_child(effect)
	effect.setup([boss],[],traffic)
	destroyed.emit()
	queue_free()
