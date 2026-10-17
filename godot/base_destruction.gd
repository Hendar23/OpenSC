extends Node3D
## Owns the base visuals after mission cleanup, until their staged demolition.
const BURST_INTERVAL := 0.35
const BURST_COUNT := 6
const COLLAPSE_TIME := 2.1
var age := 0.0
var buildings: Array[Dictionary] = []
var frames: Array[Texture2D] = []
var sound: AudioStream
var bubble_texture: Texture2D
var explosions := 0
var wrecks := 0

func setup(models: Array[Node3D], smoke: Array[Node], traffic: Node) -> void:
	name = "BaseDestruction"; add_to_group("base_destruction")
	frames = traffic.explosion_frames; sound = traffic.explosion_sound; bubble_texture = traffic.bubble_texture
	for model in models:
		model.reparent(self,true)
		var bounds := AABB(); var found := false
		for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh == null: continue
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			bounds = bounds.merge(box) if found else box; found = true
		if not found: bounds = AABB(model.global_position-Vector3.ONE,Vector3.ONE*2)
		buildings.append({"model":model,"bounds":bounds,"next":0,"collapsed":false,"delay":float(buildings.size())*0.12})
	for plume in smoke:
		if is_instance_valid(plume): plume.reparent(self,true)
	_process(0.0)

func _process(delta: float) -> void:
	age += delta
	for building in buildings:
		var elapsed: float = age-float(building.delay)
		var bounds: AABB = building.bounds
		while int(building.next) < BURST_COUNT and elapsed >= float(building.next)*BURST_INTERVAL:
			var index: int = building.next
			var angle := float(index)*TAU/3.0
			var offset := Vector3(cos(angle)*bounds.size.x*0.3,((-0.2) if index%2 == 0 else 0.25)*bounds.size.y,sin(angle)*bounds.size.z*0.3)
			_burst(bounds.get_center()+offset,clampf(bounds.size.length()*0.2,0.8,1.8))
			building.next += 1
		if not building.collapsed and elapsed >= COLLAPSE_TIME:
			building.collapsed = true
			_burst(bounds.get_center(),clampf(bounds.size.length()*0.35,1.4,3.0))
			var model: Node3D = building.model
			var wreck := preload("res://submarine_death.gd").new(); get_parent().add_child(wreck)
			wreck.global_position = bounds.get_center()
			wreck.setup_machine(model,model,bubble_texture)
			wrecks += 1; model.hide(); model.queue_free()
	if not buildings.is_empty() and buildings.all(func(building: Dictionary) -> bool: return building.collapsed): queue_free()

func _burst(point: Vector3, size: float) -> void:
	var effect := preload("res://mine_explosion.gd").new(); get_parent().add_child(effect)
	effect.global_position = point; effect.setup(frames,size,sound); explosions += 1
