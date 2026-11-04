extends RefCounted
## Retail stage-two offers and REQUIRE.TXT affordability, SC.EXE 0043d230.
const DISTRESS := ["backstab","backstab2","backstab3","backstab4"]
const CORE := {1:"walktrad2",3:"walktrad",2:"walktech",4:"walktech2"}
const CORE_FOUR := {1:"canister",3:"canister2",2:"canister3",4:"canister4"}
const CORE_THREE := {1:"diptrad",3:"diptrad2",2:"diptech",4:"diptech2"}
const QUEUES := {1:["stranded","spytrad","escort"],3:["spytrad2","bigherd","escort2","eel"],2:["breakout","fishing","spytech","recontech"],4:["breakout2","spytech2","tagtech","recontech2"]}
const STAGE_THREE := {1:["minefield","defect","bomb"],2:["disperse","fumehole","miners","aliens"],3:["rovrtn","defect2"],4:["fumehole2","miners2","aliens2"]}
const STAGE_FOUR := {1:["pwalker","backstab"],2:["puffa","backstab3"],3:["pwalker2","backstab2"],4:["puffa2","backstab4"]}
const IMPLEMENTED := ["canister","canister2","canister3","canister4","backstab","backstab2","backstab3","backstab4","puffa","puffa2","pwalker","pwalker2","stranded","spytrad","spytrad2","bigherd","fishing","breakout","breakout2","spytech","spytech2","escort","escort2","tagtech","eel","recontech","recontech2","walktrad","walktrad2","walktech","walktech2","minefield","disperse","rovrtn","fumehole","fumehole2","defect","defect2","miners","miners2","bomb","aliens","aliens2","diptrad","diptrad2","diptech","diptech2"]
const PAIRED := {"backstab":"backstab2","backstab2":"backstab","backstab3":"backstab4","backstab4":"backstab3","puffa":"puffa2","puffa2":"puffa","pwalker":"pwalker2","pwalker2":"pwalker","breakout":"breakout2","breakout2":"breakout","spytrad":"spytrad2","spytrad2":"spytrad","spytech":"spytech2","spytech2":"spytech","escort":"escort2","escort2":"escort","recontech":"recontech2","recontech2":"recontech","fumehole":"fumehole2","fumehole2":"fumehole","defect":"defect2","defect2":"defect","miners":"miners2","miners2":"miners","aliens":"aliens2","aliens2":"aliens"}

static func offering_city(id: String) -> int:
	for cores in [CORE,CORE_THREE,CORE_FOUR]:
		for city in cores:
			if cores[city] == id: return int(city)
	for city in QUEUES:
		if id in QUEUES[city]: return int(city)
	for city in STAGE_THREE:
		if id in STAGE_THREE[city]: return int(city)
	for city in STAGE_FOUR:
		if id in STAGE_FOUR[city]: return int(city)
	return 0

static func mission_stage(id: String) -> int:
	if id in CORE_FOUR.values(): return 4
	for queue in STAGE_FOUR.values():
		if id in queue: return 4
	if id in CORE_THREE.values(): return 3
	for queue in STAGE_THREE.values():
		if id in queue: return 3
	return 2

static func next_offer(progress: Dictionary, city: int) -> String:
	var stage := int(progress.campaign_stage)
	if stage not in [2,3,4]: return ""
	if stage == 2 and core_unlocked(progress) and CORE.has(city):
		var core: String = CORE[city]
		if not progress.missions.completed.has(core) and core not in progress.missions.get("unavailable",[]): return core
	if stage == 3 and core_three_unlocked(progress) and CORE_THREE.has(city):
		var core: String = CORE_THREE[city]
		if not progress.missions.completed.has(core) and core not in progress.missions.get("unavailable",[]): return core
	if stage == 4 and core_four_unlocked(progress) and CORE_FOUR.has(city):
		var core: String = CORE_FOUR[city]
		if not progress.missions.completed.has(core) and core not in progress.missions.get("unavailable",[]): return core
	var queues: Dictionary = STAGE_FOUR if stage == 4 else STAGE_THREE if stage == 3 else QUEUES
	for id: String in queues.get(city,[]):
		if id in DISTRESS and progress.missions.completed.keys().any(func(done):return done in DISTRESS): continue
		if progress.missions.completed.has(id) or id in progress.missions.get("unavailable",[]): continue
		# Published beta saves can have resolved Beluga's variant before Touka's
		# existed. Derive its exclusion from history without rewriting the save.
		if PAIRED.has(id) and progress.missions.completed.has(PAIRED[id]): continue
		return id
	return ""

static func core_unlocked(progress: Dictionary) -> bool:
	# History also covers published beta saves that predate the counters.
	var resolved := 0; var successes := 0
	for id in progress.missions.completed:
		if not IMPLEMENTED.has(id) or id in CORE.values() or mission_stage(id) != 2: continue
		resolved += 1
		if progress.missions.completed[id].get("success",false): successes += 1
	return maxi(successes,int(progress.missions.get("stage2_successes",0))) >= 5 or maxi(resolved,int(progress.missions.get("stage2_resolved",0))) >= 8

static func requirement_cost(game: Node, id: String, city: int) -> int:
	var catalogue: Dictionary = game.gameplay_catalogue
	var requirements: Dictionary = catalogue.tables.get("mission_requirements",{}).get("records",{})
	# Retail omits Tryton's row despite the shared Magnet rescue briefing.
	# Match Velcova unless the data/mod explicitly supplies Tryton's own row.
	var requirement_id := "miners" if id == "miners2" and not requirements.has(id) else id
	var needed: Array = requirements.get(requirement_id,{}).get("items",[])
	var total := 0
	var shop = preload("res://equipment_shop.gd")
	for item in needed:
		if shop.owned(game.player_progress,game.equipment,game.weapons,item) > 0: continue
		var price := int(shop.offer(catalogue,str(city),int(game.player_progress.campaign_stage),item).price)
		if price == 0:
			# Retail uses the highest price among the four cities if the offering
			# station does not sell a required tool, not the cheapest elsewhere.
			for other in [1,2,3,4]: price = maxi(price,int(shop.offer(catalogue,str(other),int(game.player_progress.campaign_stage),item).price))
		if price == 0: return 0xfffffff
		total += price
	return total

static func core_three_unlocked(progress: Dictionary) -> bool:
	var successes := 0; var resolved := 0
	for id in progress.missions.completed:
		if id not in IMPLEMENTED or mission_stage(id) != 3 or id in CORE_THREE.values(): continue
		resolved += 1
		if progress.missions.completed[id].get("success",false): successes += 1
	return maxi(successes,int(progress.missions.get("stage3_successes",0))) >= 4 or maxi(resolved,int(progress.missions.get("stage3_resolved",0))) >= 8

static func core_four_unlocked(progress: Dictionary) -> bool:
	var successes := 0; var resolved := 0
	for id in progress.missions.completed:
		if id not in IMPLEMENTED or mission_stage(id) != 4 or id in CORE_FOUR.values(): continue
		resolved += 1
		if progress.missions.completed[id].get("success",false): successes += 1
	return maxi(successes,int(progress.missions.get("stage4_successes",0))) >= 2 or maxi(resolved,int(progress.missions.get("stage4_resolved",0))) >= 3
