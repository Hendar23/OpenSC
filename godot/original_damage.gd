extends RefCounted
# Recovered SC.EXE arithmetic uses 25 simulation ticks/second and 10 raw
# shield units. OpenSC displays 100 shield points and uses a 100 kg base sub.
const TICKS_PER_SECOND := 25.0
const SHIELD_POINTS_PER_RAW := 10.0
const REFERENCE_MASS := 100.0
const BASE_SUSTAIN := 0.35
static func sustain(hull_rating: float) -> float:
	return maxf(0.05,BASE_SUSTAIN - (clampf(hull_rating,100,200) - 100.0) * 0.005)
static func radiation_protection(rating: float) -> float:
	return 1.0 - clampf(rating,0,100) * 0.008
static func terrain(speed: float, mass: float) -> float:
	return SHIELD_POINTS_PER_RAW * (speed / TICKS_PER_SECOND) / maxf(0.01,mass / REFERENCE_MASS) * BASE_SUSTAIN
static func object_contact(closing_speed: float, inflict: float) -> float:
	return SHIELD_POINTS_PER_RAW * 10.0 * (closing_speed / TICKS_PER_SECOND) * maxf(0,inflict) * BASE_SUSTAIN
static func radiation(strength_at_one_unit: float, distance: float) -> float:
	# Avoid a singularity if physics places the source at the submarine centre.
	return strength_at_one_unit / maxf(0.1,distance)
