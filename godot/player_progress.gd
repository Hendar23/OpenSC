extends RefCounted

const DEFAULT_STATUS := {"hull_strength":100,"top_speed":100,"shields":100,"radiation_shield":0,"credits":0}

static func restore(saved: Variant = {}) -> Dictionary:
	var result := {"campaign_stage":1,"mission":"None","standing":{},"status":DEFAULT_STATUS.duplicate(),"hold":{},"cargo":{},"suckomat":[],"pending_deliveries":{},"markets":{}}
	if not saved is Dictionary: return result
	result.markets = preload("res://commodity_market.gd").restore(saved.get("markets",{}))
	result.economy = {"production_elapsed":0.0,"trader_elapsed":0.0}
	var clock: Variant = saved.get("economy",{})
	if clock is Dictionary:
		if clock.get("quote_version",0) == 1: result.economy.quote_version = 1
		for field in result.economy:
			var value: Variant = clock.get(field,0.0)
			if (value is int or value is float) and is_finite(float(value)) and value >= 0:
				result.economy[field] = fmod(float(value),30.0 if field == "production_elapsed" else 150.1)
	if saved.get("pending_deliveries") is Dictionary:
		for city in saved.pending_deliveries:
			var goods: Variant = saved.pending_deliveries[city]
			if not goods is Dictionary: continue
			var validated: Dictionary = restore({"cargo":goods}).cargo
			if not validated.is_empty(): result.pending_deliveries[str(city)] = validated
	var stage: Variant = saved.get("campaign_stage",1)
	if (stage is int or stage is float) and is_finite(float(stage)): result.campaign_stage = clampi(int(stage),1,4)
	if saved.get("mission") is String: result.mission = saved.mission.left(128)
	if saved.get("standing") is Dictionary:
		for race in saved.standing:
			if saved.standing[race] in ["bad","neutral","good"]: result.standing[str(race)] = saved.standing[race]
	if saved.get("status") is Dictionary:
		for key in DEFAULT_STATUS:
			var value: Variant = saved.status.get(key,DEFAULT_STATUS[key])
			if (value is int or value is float) and is_finite(float(value)): result.status[key] = maxi(0,int(value))
	result.status.hull_strength = clampi(result.status.hull_strength,100,200)
	result.status.radiation_shield = clampi(result.status.radiation_shield,0,100)
	result.status.shields = clampi(result.status.shields,0,100)
	if saved.get("hold") is Dictionary:
		for id in saved.hold:
			var count: Variant = saved.hold[id]
			if id is String and (count is int or count is float) and is_finite(float(count)) and count > 0:
				result.hold[id] = clampi(int(count),1,9999)
	if saved.get("cargo") is Dictionary:
		for id in saved.cargo:
			var count: Variant = saved.cargo[id]
			if id is String and (count is int or count is float) and is_finite(float(count)) and count > 0: result.cargo[id] = clampi(int(count),1,999999)
	if saved.get("suckomat") is Array:
		for item in saved.suckomat:
			if item is String and not item.is_empty() and result.suckomat.size() < 5: result.suckomat.append(item)
	return result
static func collect_deliveries(progress: Dictionary, city_id: int) -> void:
	var pending: Dictionary = progress.get("pending_deliveries",{})
	var key := str(city_id)
	for commodity in pending.get(key,{}):
		progress.cargo[commodity] = int(progress.cargo.get(commodity,0)) + int(pending[key][commodity])
	pending.erase(key)
