extends RefCounted

static func shield_repair(catalogue: Dictionary, city_id: String, stage: int) -> Dictionary:
	var tables: Dictionary = catalogue.get("tables",{})
	var text: Dictionary = tables.get("equipment_text",{}).get("records",{}).get("shield",{})
	var definition: Dictionary = tables.get("equipment",{}).get("records",{}).get("shield",{})
	var pricing_stage := 4 if stage >= 4 else 3 if stage >= 3 else 1
	var prices: Dictionary = tables.get("equipment_prices.%d" % pricing_stage,{}).get("records",{}).get("shield",{})
	var city_record: Dictionary = tables.get("city_info",{}).get("records",{}).get(city_id,{})
	var city := str(city_record.get("shop_price_key",str(city_record.get("name","")).get_slice(" ",0)))
	return {"id":"shield","name":text.get("name","Shield Repair"),"description":text.get("Description","Restores shields to full strength."),"available":not city.is_empty() and prices.has(city + " buy") and int(prices[city + " buy"]) > 0,"price":maxi(0,int(prices.get(city + " buy",0))),"sell_price":maxi(0,int(prices.get(city + " sell",0))),"maximum":maxi(1,int(definition.get("Maximum",1))),"info_bitmap":"INTROTEX/" + str(definition.get("Info Pic","wshields")).to_upper() + ".BMP"}

static func buy(progress: Dictionary, offer: Dictionary) -> String:
	if not offer.get("available",false): return "Shield Repair is not sold at this station."
	if int(progress.status.credits) < int(offer.price): return "Not enough credits."
	progress.status.credits -= int(offer.price)
	progress.hold[offer.id] = int(progress.hold.get(offer.id,0)) + 1
	return "Shield Repair placed in the hold."

static func consume_repair(progress: Dictionary, pilot: Node) -> String:
	if int(progress.hold.get("shield",0)) <= 0: return "Select Shield Repair from the hold."
	if pilot.dead: return "The submarine is destroyed."
	if pilot.health >= pilot.max_health: return "Shields are already at full strength."
	progress.hold.shield -= 1
	if progress.hold.shield == 0: progress.hold.erase("shield")
	pilot.restore_health(pilot.max_health,pilot.max_health)
	return "Shields restored to full strength."
