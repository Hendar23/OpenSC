extends RefCounted
## Raw shield storage shared by NPC controllers; receivers apply sustain once.
var capacity := 4.0
var sustain := 0.1
var remaining := 4.0
func configure(maximum: float, multiplier: float) -> void:
	capacity = maximum; sustain = multiplier; remaining = capacity
func hit(strength: float) -> bool:
	if not is_finite(strength) or strength <= 0 or remaining <= 0: return false
	remaining = maxf(0,remaining - strength * sustain)
	return true
