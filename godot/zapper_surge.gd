extends Node
## A transient material pass on the target's own animated geometry.
const SHADER = preload("res://zapper_surge.gdshader")
const FADE_TIME := 0.7
const SURGE_TIME := 0.18
const HOLD_STRENGTH := 0.55
const NODE_NAME := "ZapperHullSurge"

var bindings: Dictionary[MeshInstance3D, Material] = {}
var passes: Dictionary[Material, ShaderMaterial] = {}
var since_hit := 0.0
var phase := 0.0
var strength := 1.0

static func strike(body: Node3D) -> void:
	if not is_instance_valid(body) or not body.is_inside_tree() or body.is_queued_for_deletion(): return
	if not (body.has_method("take_damage") or body.has_method("take_weapon_damage")) or body.get("dead") == true: return
	var model := _model_for(body)
	if not model.is_visible_in_tree(): return
	var active := model.get_node_or_null(NODE_NAME)
	if active != null:
		if not active.is_queued_for_deletion(): active.since_hit = 0.0
		return
	var effect: Node = load("res://zapper_surge.gd").new()
	effect.name = NODE_NAME
	model.add_child(effect)

static func _model_for(body: Node3D) -> Node3D:
	var visual := body.get("visual") as Node3D
	if is_instance_valid(visual): return visual
	if body.has_meta("asset_source"): return body
	# Scenery weapons and traffic use a collision body inside the actor model.
	var parent := body.get_parent() as Node3D
	if parent != null and parent.has_meta("asset_source"): return parent
	return body

func _enter_tree() -> void:
	# Streamed fish can leave the tree and return as a different individual.
	if since_hit >= FADE_TIME:
		queue_free()
		return
	var model := get_parent() as Node3D
	var meshes := model.find_children("*","MeshInstance3D",true,false)
	if model is MeshInstance3D: meshes.push_front(model)
	var bounds := AABB()
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null or mesh.top_level or not mesh.is_visible_in_tree(): continue
		var box := mesh.global_transform * mesh.get_aabb()
		bounds = bounds.merge(box) if not bindings.is_empty() else box
		bindings[mesh] = mesh.material_overlay
	var size := maxf(0.01,bounds.get_longest_axis_size())
	for mesh in bindings:
		var original := bindings[mesh]
		if not passes.has(original):
			var material := ShaderMaterial.new()
			material.shader = SHADER
			material.render_priority = 1
			material.next_pass = original
			material.set_shader_parameter("arc_scale",1.0 / size)
			passes[original] = material
		mesh.material_overlay = passes[original]
	if bindings.is_empty():
		queue_free()
	else:
		_update_materials(0.0)

func _process(delta: float) -> void:
	since_hit += delta
	phase += delta
	if since_hit >= FADE_TIME:
		_restore_materials()
		queue_free()
		return
	_update_materials(delta)

func _update_materials(delta: float) -> void:
	var surge := 1.0 - smoothstep(0.0,SURGE_TIME,phase)
	var remaining := 1.0 - smoothstep(0.0,FADE_TIME,since_hit)
	strength = move_toward(strength,lerpf(HOLD_STRENGTH,1.0,surge) * remaining,9.0 * delta)
	for material in passes.values():
		material.set_shader_parameter("arc_phase",phase)
		material.set_shader_parameter("arc_strength",strength)

func _exit_tree() -> void:
	since_hit = FADE_TIME
	_restore_materials()

func _restore_materials() -> void:
	for mesh in bindings:
		if is_instance_valid(mesh) and mesh.material_overlay == passes[bindings[mesh]]:
			mesh.material_overlay = bindings[mesh]
	bindings.clear()
	passes.clear()
