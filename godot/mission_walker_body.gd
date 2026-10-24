extends "res://mission_cargo.gd"
const TOW_MASS := 37.5
const FREE_MASS := 3750.0
## Project 13 hit notifications: SC.EXE 004117b0, case 11.
signal weapon_hit(strength: float, source: Vector3, attacker: Node3D, kind: String, head_hit: bool)
var detached := false
var impact_velocity := Vector3.ZERO
var contacts := {}
var raw_impact_mass := 75.0

func set_towing_attached(on: bool) -> void:
	if not detached: return
	# Apply the retail mass change before the magnet calculates cable/engine
	# load on this very tick, rather than briefly loading its free-body mass.
	mass = TOW_MASS if on else FREE_MASS
	raw_impact_mass = 0.75 if on else 75.0

func take_located_weapon_damage(strength: float, source: Vector3, attacker: Node3D, kind: String, _impact: Vector3, shape_index: int) -> void:
	if dead or delivered: return
	var owner_node: Object = shape_owner_get_owner(shape_find_owner(shape_index))
	var head_hit: bool = detached or (owner_node != null and owner_node.get_meta("walker_head",false))
	weapon_hit.emit(strength,source,attacker,kind,head_hit)
	if detached: super.take_weapon_damage(strength,source)

func take_typed_weapon_damage(strength: float, source: Vector3, attacker: Node3D, kind: String) -> void:
	if dead or delivered: return
	# Legacy/non-ray callers have no confirmed head contact. Never infer it
	# from the firing submarine's height, which is unrelated to the impact.
	weapon_hit.emit(strength,source,attacker,kind,detached)
	if detached: super.take_weapon_damage(strength,source)

func take_weapon_damage_from(strength: float, source: Vector3, attacker: Node3D) -> void:
	take_typed_weapon_damage(strength,source,attacker,"")

func take_weapon_damage(strength: float, source: Vector3 = Vector3.ZERO) -> void:
	take_typed_weapon_damage(strength,source,null,"")

func take_damage(amount: float, source: Vector3 = Vector3.ZERO) -> void:
	# Physical knocks can destroy the unstable head; the disabled chassis does
	# not turn an incidental collision into one of its scripted weapon hits.
	if detached: super.take_weapon_damage(amount / 3.0,source)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	super._integrate_forces(state)
	if not detached or dead or delivered: return
	var current := {}; var strongest := 0.0
	for index in state.get_contact_count():
		var collider := state.get_contact_collider_object(index) as CollisionObject3D
		if collider == null or collider is RigidBody3D or collider.collision_layer & 1 == 0: continue
		var identity := state.get_contact_collider_id(index)
		var normal := state.get_contact_local_normal(index)
		if not current.has(identity): current[identity] = []
		current[identity].append(normal)
		var previous: Array = contacts.get(identity,[])
		if previous.any(func(old: Vector3) -> bool: return old.dot(normal) > 0.9): continue
		var closing := maxf(0,-(impact_velocity-state.get_contact_collider_velocity_at_position(index)).dot(normal))
		strongest = maxf(strongest,closing)
	contacts = current; impact_velocity = state.linear_velocity
	# Original terrain response 00466620: |normal velocity| / raw mass,
	# then sustain; only above .02 per 25-Hz tick. Do not damage a resting head
	# continuously, or count the magnet's clamp/contact as an impact.
	if strongest > 0.5: take_weapon_damage.call_deferred((strongest/25.0)/raw_impact_mass,global_position)
