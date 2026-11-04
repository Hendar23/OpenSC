extends RefCounted
## Campaign stage controls availability; encounter family selects its controller.
## The three original encounter flows still live in mission_dispatcher.gd.
const FAMILIES := {
	"nuclear_stockpile":{"ids":["canister","canister2","canister3","canister4"],"script":preload("res://nuclear_stockpile.gd")},
	"allied_distress":{"ids":["backstab","backstab2","backstab3","backstab4"],"script":preload("res://allied_distress.gd")},
	"pirate_stockpile":{"ids":["puffa","puffa2"],"script":preload("res://pirate_stockpile.gd")},
	"bacau_rescue":{"ids":["stranded"],"script":null},
	"prison_breakout":{"ids":["breakout","breakout2"],"script":null},
	"bohine_covert":{"ids":["spytrad","spytrad2"],"script":null},
	"fishing":{"ids":["fishing","bigherd"],"script":preload("res://fishing_missions.gd")},
	"support":{"ids":["spytech","spytech2","escort","escort2","tagtech","eel","recontech","recontech2"],"script":preload("res://stage_two_remaining.gd")},
	"genocide_weapon":{"ids":["walktrad","walktrad2","walktech","walktech2"],"script":preload("res://genocide_weapon.gd")},
	"terrorists":{"ids":["minefield"],"script":preload("res://thwart_terrorists.gd")},
	"dock_rescue":{"ids":["disperse","rovrtn"],"script":preload("res://stage_three_missions.gd")},
	"volcano":{"ids":["fumehole","fumehole2"],"script":preload("res://volcanic_disaster.gd")},
	"defection":{"ids":["defect","defect2"],"script":preload("res://covert_defection.gd")},
	"student_rescue":{"ids":["miners","miners2"],"script":preload("res://student_rescue.gd")},
	"bomb_disposal":{"ids":["bomb"],"script":preload("res://bomb_disposal.gd")},
	"queen_jellyfish":{"ids":["aliens","aliens2"],"script":preload("res://queen_jellyfish.gd")},
	"diplomats":{"ids":["diptrad","diptrad2","diptech","diptech2"],"script":preload("res://escort_diplomats.gd")},
	"rampaging_walker":{"ids":["pwalker","pwalker2"],"script":preload("res://rampaging_walker.gd")},
}

static func family_for(id: String) -> String:
	for family in FAMILIES:
		if id in FAMILIES[family].ids: return family
	return ""
