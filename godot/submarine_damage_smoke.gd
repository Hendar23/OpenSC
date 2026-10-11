extends "res://smoke_emitter.gd"

# Shared by player and future NPC subs: supply a hull visual and forward health
# changes to set_health(). No input, player singleton or AI dependencies.
# SC.EXE 0x47f100 transforms (0,0,-0.5) by the hull matrix. Low-health
# callers compare raw health against 1.5 and emit on random & 3 == 0.
const Damage = preload("res://original_damage.gd")
const DEFAULT_TRIGGER := 1.5 * Damage.SHIELD_POINTS_PER_RAW
var trigger_health := DEFAULT_TRIGGER
var hull_offset := Vector3(0,0,-0.5)
var hull: Node3D
var damaged := false

func setup(visual: Node3D, folder: String) -> void:
	hull = visual
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	configure(folder,{"enabled":false,"emission_rate":Damage.TICKS_PER_SECOND * 0.25,"start_size":0.12,"end_size":0.8,"lifetime":6.0,"rise_speed":0.3,"spread":0.08,"opacity":0.6})

func set_health(remaining: float, _capacity: float = 100.0) -> void:
	# This is an absolute threshold in the original, not a fraction of hull
	# armour. NPC types can choose their own trigger without another effect.
	damaged = is_finite(remaining) and remaining > 0.0 and remaining < trigger_health
	enabled = damaged and is_instance_valid(hull) and hull.is_visible_in_tree()

func emission_origin() -> Vector3:
	if not is_instance_valid(hull): return super.emission_origin()
	return hull.get_global_transform_interpolated() * hull_offset

func _process(delta: float) -> void:
	enabled = damaged and is_instance_valid(hull) and hull.is_visible_in_tree()
	super._process(delta)
