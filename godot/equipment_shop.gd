extends RefCounted

const ITEMS := ["shield", "hullstr", "radoff", "deep_sea_lights", "suckomat", "zapper", "magnet", "grapple", "zapperup", "bigears", "escape", "depthl", "depth"]
const UPGRADES := {"hullstr":{"stat":"hull_strength","maximum":200},"radoff":{"stat":"radiation_shield","maximum":100},"zapperup":{"stat":"zapper_upgrade","maximum":1,"increment":1}}

static func upgrade_available(progress: Dictionary, id: String) -> bool:
	if not UPGRADES.has(id): return true
	var upgrade: Dictionary = UPGRADES[id]
	return int(progress.status.get(upgrade.stat,0)) < int(upgrade.maximum)

static func use_item(progress: Dictionary, pilot: Node, id: String) -> String:
	if id == "shield": return consume_repair(progress,pilot)
	if not UPGRADES.has(id) or int(progress.hold.get(id,0)) <= 0: return ""
	if pilot.dead: return "The submarine is destroyed."
	if not upgrade_available(progress,id): return "Upgrade already at maximum."
	var upgrade: Dictionary = UPGRADES[id]
	progress.status[upgrade.stat] = mini(int(upgrade.maximum),int(progress.status.get(upgrade.stat,0)) + int(upgrade.get("increment",20)))
	progress.hold[id] -= 1
	if progress.hold[id] == 0: progress.hold.erase(id)
	pilot.hull_rating = float(progress.status.hull_strength)
	pilot.radiation_rating = float(progress.status.radiation_shield)
	return ""
const SLOTS := {"zapper":9,"deep_sea_lights":5,"suckomat":3,"magnet":3,"grapple":3,"escape":3,"bigears":4,"depthl":7}

static func shield_repair(catalogue: Dictionary, city_id: String, stage: int, testing: bool = false) -> Dictionary:
	return offer(catalogue,city_id,stage,"shield",testing)

static func offers(catalogue: Dictionary, city_id: String, stage: int, testing: bool = false) -> Dictionary:
	var result := {}
	for id in ITEMS: result[id] = offer(catalogue,city_id,stage,id,testing)
	return result

static func offer(catalogue: Dictionary, city_id: String, stage: int, id: String, testing: bool = false) -> Dictionary:
	var source_id := "lights" if id == "deep_sea_lights" else id
	var tables: Dictionary = catalogue.get("tables",{})
	var text: Dictionary = tables.get("equipment_text",{}).get("records",{}).get(source_id,{})
	var definition: Dictionary = tables.get("equipment",{}).get("records",{}).get(source_id,{})
	var pricing_stage := 4 if stage >= 4 else 3 if stage >= 3 else 1
	var prices: Dictionary = tables.get("equipment_prices.%d" % pricing_stage,{}).get("records",{}).get(source_id,{})
	var city_record: Dictionary = tables.get("city_info",{}).get("records",{}).get(city_id,{})
	var city := str(city_record.get("shop_price_key",str(city_record.get("name","")).get_slice(" ",0)))
	if testing:
		prices = prices.duplicate()
		if int(prices.get(city + " buy",0)) <= 0:
			var fallback := 0
			for level in [4,3,1]:
				var record: Dictionary = tables.get("equipment_prices.%d" % level,{}).get("records",{}).get(source_id,{})
				for key in record:
					if str(key).ends_with(" buy") and int(record[key]) > 0: fallback = int(record[key]) if fallback == 0 else mini(fallback,int(record[key]))
			prices[city + " buy"] = maxi(1,fallback)
	return {"id":id,"name":text.get("name",id.capitalize()),"description":text.get("Description","Restores shields to full strength."),"available":(testing or not city.is_empty()) and prices.has(city + " buy") and int(prices[city + " buy"]) > 0,"price":maxi(0,int(prices.get(city + " buy",0))),"sell_price":maxi(0,int(prices.get(city + " sell",0))),"quantity":maxi(1,int(definition.get("Default",4))) if id == "depth" else 1,"maximum":maxi(1,int(definition.get("Maximum",1))),"slot":SLOTS.get(id,0),"square_bitmap":"INTROTEX/" + str(definition.get("Sq Pic","sqshld")).to_upper() + ".BMP","info_bitmap":"INTROTEX/" + str(definition.get("Info Pic","wshields")).to_upper() + ".BMP"}

static func buy(progress: Dictionary, offer: Dictionary) -> String:
	if not offer.get("available",false): return str(offer.name) + " is not sold at this station."
	if not upgrade_available(progress,str(offer.id)): return "Upgrade already at maximum."
	if UPGRADES.has(str(offer.id)) and int(progress.hold.get(offer.id,0)) >= int(offer.maximum): return "Already owned."
	var quantity := int(offer.get("quantity",1))
	if offer.id != "shield" and int(progress.hold.get(offer.id,0)) + quantity > int(offer.maximum): return "No room for another pack." if quantity > 1 else "Already owned."
	if int(progress.status.credits) < int(offer.price): return "Not enough credits."
	progress.status.credits -= int(offer.price)
	progress.hold[offer.id] = int(progress.hold.get(offer.id,0)) + quantity
	if offer.id == "bigears": progress.ammunition.bigears = 5
	# Retail shop 00440970: launcher purchase includes two packs of four.
	# Keep individual charges in hold.depth, preserving published beta saves.
	if offer.id == "depthl": progress.hold.depth = mini(80,int(progress.hold.get("depth",0)) + 8)
	return ""

static func sell(progress: Dictionary, offer: Dictionary) -> String:
	var quantity := int(offer.get("quantity",1))
	if int(offer.get("sell_price",0)) <= 0 or int(progress.hold.get(offer.id,0)) < quantity: return "Item cannot be sold." if quantity == 1 else "A full pack of four charges is needed."
	progress.hold[offer.id] -= quantity
	if progress.hold[offer.id] == 0: progress.hold.erase(offer.id)
	progress.status.credits += int(offer.sell_price)
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
	if slot not in [3,4,5,7,9]: return ""
	var old: String = installed(equipment,weapons).get(slot,"")
	var incoming := selected if SLOTS.get(selected,0) == slot and int(progress.hold.get(selected,0)) > 0 else ""
	if incoming.is_empty() and old.is_empty(): return ""
	if not incoming.is_empty():
		progress.hold[incoming] -= 1
		if progress.hold[incoming] == 0: progress.hold.erase(incoming)
	if not old.is_empty(): progress.hold[old] = int(progress.hold.get(old,0)) + 1
	var ids: Array = equipment.mounted.map(func(item: Dictionary) -> String: return str(item.id))
	if slot in [7,9]:
		var arms: Array = weapons.mounted.map(func(item: Dictionary) -> String: return str(item.id))
		arms.erase(old)
		if not incoming.is_empty(): arms.append(incoming)
		weapons.set_installed(arms)
	else:
		ids.erase(old)
		if not incoming.is_empty(): ids.append(incoming)
		equipment.set_installed(ids)
	return ""

static func owned(progress: Dictionary, equipment: Node, weapons: Node, id: String) -> int:
	return int(progress.hold.get(id,0)) + int(id in installed(equipment,weapons).values())
