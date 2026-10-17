extends RefCounted
## Retail stage-two offers and REQUIRE.TXT affordability, SC.EXE 0043d230.
const OPENING := {1:"stranded",3:"spytrad2",2:"breakout",4:"breakout2"}
const IMPLEMENTED := ["stranded","spytrad2","breakout","breakout2"]
const PAIRED := {"breakout":"breakout2","breakout2":"breakout"}

static func next_offer(progress: Dictionary, city: int) -> String:
	if int(progress.campaign_stage) != 2: return ""
	var id: String = OPENING.get(city,"")
	if progress.missions.completed.has(id) or id in progress.missions.get("unavailable",[]): return ""
	return id

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
