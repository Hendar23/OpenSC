extends Node
## Observe light lifetimes rather than rescanning the whole world every frame.
const Flare = preload("res://lens_flare.gd")
const Searchlight = preload("res://searchlight.gd")

func _ready() -> void:
	get_tree().node_added.connect(_observe)
	for node in get_parent().find_children("*","Node3D",true,false): _observe(node)

func _observe(node: Node) -> void:
	if node is Light3D or node is Searchlight:
		_install.call_deferred(node.get_instance_id())
	elif node.name == "SoftBeam" and node.get_parent() != null and node.get_parent().get_parent() is Searchlight:
		_install.call_deferred(node.get_parent().get_parent().get_instance_id())

func _install(id: int) -> void:
	if not is_instance_id_valid(id): return
	var node := instance_from_id(id) as Node
	if node == null or not node.is_inside_tree() or not get_parent().is_ancestor_of(node): return
	# Replay already captures the actual flare mesh and its animated uniforms.
	# Do not add a second live flare to its disabled light proxies.
	if node.process_mode == Node.PROCESS_MODE_DISABLED: return
	Flare.attach(node)
