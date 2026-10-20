extends RefCounted
## Retail stage-two offers and REQUIRE.TXT affordability, SC.EXE 0043d230.
const QUEUES := {1:["stranded","spytrad","escort"],3:["spytrad2","bigherd","escort2","eel"],2:["breakout","fishing","spytech","recontech"],4:["breakout2","spytech2","tagtech","recontech2"]}
const IMPLEMENTED := ["stranded","spytrad","spytrad2","bigherd","fishing","breakout","breakout2","spytech","spytech2","escort","escort2","tagtech","eel","recontech","recontech2"]
const PAIRED := {"breakout":"breakout2","breakout2":"breakout","spytrad":"spytrad2","spytrad2":"spytrad","spytech":"spytech2","spytech2":"spytech","escort":"escort2","escort2":"escort","recontech":"recontech2","recontech2":"recontech"}

static func offering_city(id: String) -> int:
	for city in QUEUES:
		if id in QUEUES[city]: return int(city)
	return 0

static func next_offer(progress: Dictionary, city: int) -> String:
	if int(progress.campaign_stage) != 2: return ""
	for id: String in QUEUES.get(city,[]):
		if progress.missions.completed.has(id) or id in progress.missions.get("unavailable",[]): continue
		# Published beta saves can have resolved Beluga's variant before Touka's
		# existed. Derive its exclusion from history without rewriting the save.
		if PAIRED.has(id) and progress.missions.completed.has(PAIRED[id]): continue
		return id
	return ""

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
