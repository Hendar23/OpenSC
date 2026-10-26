extends RefCounted
## Retail stage-two offers and REQUIRE.TXT affordability, SC.EXE 0043d230.
const CORE := {1:"walktrad2",3:"walktrad",2:"walktech",4:"walktech2"}
const QUEUES := {1:["stranded","spytrad","escort"],3:["spytrad2","bigherd","escort2","eel"],2:["breakout","fishing","spytech","recontech"],4:["breakout2","spytech2","tagtech","recontech2"]}
const STAGE_THREE := {1:["minefield","defect"],2:["disperse","fumehole"],3:["rovrtn","defect2"],4:["fumehole2"]}
const IMPLEMENTED := ["stranded","spytrad","spytrad2","bigherd","fishing","breakout","breakout2","spytech","spytech2","escort","escort2","tagtech","eel","recontech","recontech2","walktrad","walktrad2","walktech","walktech2","minefield","disperse","rovrtn","fumehole","fumehole2","defect","defect2"]
const PAIRED := {"breakout":"breakout2","breakout2":"breakout","spytrad":"spytrad2","spytrad2":"spytrad","spytech":"spytech2","spytech2":"spytech","escort":"escort2","escort2":"escort","recontech":"recontech2","recontech2":"recontech","fumehole":"fumehole2","fumehole2":"fumehole","defect":"defect2","defect2":"defect"}

static func offering_city(id: String) -> int:
	for city in CORE:
		if CORE[city] == id: return int(city)
	for city in QUEUES:
		if id in QUEUES[city]: return int(city)
	for city in STAGE_THREE:
		if id in STAGE_THREE[city]: return int(city)
	return 0

static func mission_stage(id: String) -> int:
	for queue in STAGE_THREE.values():
		if id in queue: return 3
	return 2

static func next_offer(progress: Dictionary, city: int) -> String:
	var stage := int(progress.campaign_stage)
	if stage not in [2,3]: return ""
	if stage == 2 and core_unlocked(progress) and CORE.has(city):
		var core: String = CORE[city]
		if not progress.missions.completed.has(core) and core not in progress.missions.get("unavailable",[]): return core
	var queues: Dictionary = STAGE_THREE if stage == 3 else QUEUES
	for id: String in queues.get(city,[]):
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
	var needed: Array = catalogue.tables.get("mission_requirements",{}).get("records",{}).get(id,{}).get("items",[])
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
