extends RefCounted
# Recovered SC.EXE arithmetic uses 25 simulation ticks/second and 10 raw
# shield units. OpenSC displays 100 shield points and uses a 100 kg base sub.
const TICKS_PER_SECOND := 25.0
const SHIELD_POINTS_PER_RAW := 10.0
const REFERENCE_MASS := 100.0
const BASE_SUSTAIN := 0.35
# Mine callback 0x4314a0: inflict/distance, x10 against the player,
# x4 against other mines. Range query 0x495650 includes target bounds.
static func mine_falloff(distance: float) -> float:
	return 1.0 / maxf(0.1,distance)

static func mine_raw_damage(base_hull_damage: float, distance: float, target_is_mine: bool = false) -> float:
	return base_hull_damage / (SHIELD_POINTS_PER_RAW * BASE_SUSTAIN) * mine_falloff(distance) * (0.4 if target_is_mine else 0.1)

static func sustain(hull_rating: float) -> float:
	return maxf(0.05,BASE_SUSTAIN - (clampf(hull_rating,100,200) - 100.0) * 0.005)
static func radiation_protection(rating: float) -> float:
	return 1.0 - clampf(rating,0,100) * 0.008
static func terrain(speed: float, mass: float) -> float:
	return SHIELD_POINTS_PER_RAW * (speed / TICKS_PER_SECOND) / maxf(0.01,mass / REFERENCE_MASS) * BASE_SUSTAIN
static func object_contact(closing_speed: float, inflict: float) -> float:
	return SHIELD_POINTS_PER_RAW * 10.0 * (closing_speed / TICKS_PER_SECOND) * maxf(0,inflict) * BASE_SUSTAIN
static func radiation_strength(inflict: float) -> float:
	return inflict * TICKS_PER_SECOND * SHIELD_POINTS_PER_RAW * BASE_SUSTAIN
static func radiation(strength_at_one_unit: float, distance: float) -> float:
	# Avoid a singularity if physics places the source at the submarine centre.
	return strength_at_one_unit / maxf(0.1,distance)

# Weapon strength is raw shield loss before the receiver's sustain multiplier.
# Keep each body's existing storage scale explicit: creatures/objects are raw,
# while the player stores the ten-times larger displayed shield points.
static func weapon(target: Node3D, raw_strength: float, source: Vector3) -> void:
	if raw_strength <= 0.0 or not is_finite(raw_strength): return
	if target.has_method("take_weapon_damage"):
		target.take_weapon_damage(raw_strength,source)
	elif target.has_method("take_damage"):
		target.take_damage(raw_strength * float(target.get_meta("damage_sustain",1.0)),source)
