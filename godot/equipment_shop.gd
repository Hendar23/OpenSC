extends RefCounted

const ITEMS := ["shield", "hullstr", "radoff", "deep_sea_lights", "suckomat", "zapper", "magnet", "grapple"]
const UPGRADES := {"hullstr":{"stat":"hull_strength","maximum":200},"radoff":{"stat":"radiation_shield","maximum":100}}

static func upgrade_available(progress: Dictionary, id: String) -> bool:
	if not UPGRADES.has(id): return true
	var upgrade: Dictionary = UPGRADES[id]
	return int(progress.status[upgrade.stat]) < int(upgrade.maximum)

static func use_item(progress: Dictionary, pilot: Node, id: String) -> String:
	if id == "shield": return consume_repair(progress,pilot)
	if not UPGRADES.has(id) or int(progress.hold.get(id,0)) <= 0: return ""
	if pilot.dead: return "The submarine is destroyed."
	if not upgrade_available(progress,id): return "Upgrade already at maximum."
	var upgrade: Dictionary = UPGRADES[id]
	progress.status[upgrade.stat] = mini(int(upgrade.maximum),int(progress.status[upgrade.stat]) + 20)
	progress.hold[id] -= 1
	if progress.hold[id] == 0: progress.hold.erase(id)
	pilot.hull_rating = float(progress.status.hull_strength)
	pilot.radiation_rating = float(progress.status.radiation_shield)
	return ""
const SLOTS := {"zapper":9,"deep_sea_lights":5,"suckomat":3,"magnet":3,"grapple":3}

static func shield_repair(catalogue: Dictionary, city_id: String, stage: int) -> Dictionary:
	return offer(catalogue,city_id,stage,"shield")

static func offers(catalogue: Dictionary, city_id: String, stage: int) -> Dictionary:
	var result := {}
	for id in ITEMS: result[id] = offer(catalogue,city_id,stage,id)
	return result

static func offer(catalogue: Dictionary, city_id: String, stage: int, id: String) -> Dictionary:
	var source_id := "lights" if id == "deep_sea_lights" else id
	var tables: Dictionary = catalogue.get("tables",{})
	var text: Dictionary = tables.get("equipment_text",{}).get("records",{}).get(source_id,{})
	var definition: Dictionary = tables.get("equipment",{}).get("records",{}).get(source_id,{})
	var pricing_stage := 4 if stage >= 4 else 3 if stage >= 3 else 1
	var prices: Dictionary = tables.get("equipment_prices.%d" % pricing_stage,{}).get("records",{}).get(source_id,{})
	var city_record: Dictionary = tables.get("city_info",{}).get("records",{}).get(city_id,{})
	var city := str(city_record.get("shop_price_key",str(city_record.get("name","")).get_slice(" ",0)))
	return {"id":id,"name":text.get("name",id.capitalize()),"description":text.get("Description","Restores shields to full strength."),"available":not city.is_empty() and prices.has(city + " buy") and int(prices[city + " buy"]) > 0,"price":maxi(0,int(prices.get(city + " buy",0))),"sell_price":maxi(0,int(prices.get(city + " sell",0))),"maximum":maxi(1,int(definition.get("Maximum",1))),"slot":SLOTS.get(id,0),"square_bitmap":"INTROTEX/" + str(definition.get("Sq Pic","sqshld")).to_upper() + ".BMP","info_bitmap":"INTROTEX/" + str(definition.get("Info Pic","wshields")).to_upper() + ".BMP"}

static func buy(progress: Dictionary, offer: Dictionary) -> String:
	if not offer.get("available",false): return str(offer.name) + " is not sold at this station."
	if not upgrade_available(progress,str(offer.id)): return "Upgrade already at maximum."
	if UPGRADES.has(str(offer.id)) and int(progress.hold.get(offer.id,0)) >= int(offer.maximum): return "Already owned."
	if int(progress.status.credits) < int(offer.price): return "Not enough credits."
	progress.status.credits -= int(offer.price)
	progress.hold[offer.id] = int(progress.hold.get(offer.id,0)) + 1
	return ""

static func consume_repair(progress: Dictionary, pilot: Node) -> String:
	if int(progress.hold.get("shield",0)) <= 0: return "Select Shield Repair from the hold."
	if pilot.dead: return "The submarine is destroyed."
	if pilot.health >= pilot.max_health: return "Shields are already at full strength."
	progress.hold.shield -= 1
	if progress.hold.shield == 0: progress.hold.erase("shield")
	pilot.restore_health(pilot.max_health,pilot.max_health)
	return ""

static func installed(equipment: Node, weapons: Node) -> Dictionary:
	var result := {}
	for item in equipment.mounted + weapons.mounted: result[SLOTS.get(item.id,0)] = item.id
	return result

static func swap(progress: Dictionary, equipment: Node, weapons: Node, slot: int, selected: String) -> String:
	if slot not in [3,5,9]: return ""
	var old: String = installed(equipment,weapons).get(slot,"")
	var incoming := selected if SLOTS.get(selected,0) == slot and int(progress.hold.get(selected,0)) > 0 else ""
	if incoming.is_empty() and old.is_empty(): return ""
	if not incoming.is_empty():
		progress.hold[incoming] -= 1
		if progress.hold[incoming] == 0: progress.hold.erase(incoming)
	if not old.is_empty(): progress.hold[old] = int(progress.hold.get(old,0)) + 1
	var ids: Array = equipment.mounted.map(func(item: Dictionary) -> String: return str(item.id))
	if slot == 9: weapons.set_installed([incoming] if not incoming.is_empty() else [])
	else:
		ids.erase(old)
		if not incoming.is_empty(): ids.append(incoming)
		equipment.set_installed(ids)
	return ""

static func owned(progress: Dictionary, equipment: Node, weapons: Node, id: String) -> int:
	return int(progress.hold.get(id,0)) + int(id in installed(equipment,weapons).values())
