extends RefCounted

static func city_key(catalogue: Dictionary, city_id: String) -> String:
	var city: Dictionary = catalogue.get("tables",{}).get("city_info",{}).get("records",{}).get(city_id,{})
	var key := str(city.get("shop_price_key",str(city.get("name","")).get_slice(" ",0))).to_lower()
	return "factory" if key == "refinery" else key

static func restore(saved: Variant) -> Dictionary:
	var result := {}
	if not saved is Dictionary: return result
	for city in saved:
		if not city is String or not saved[city] is Dictionary: continue
		var records := {}
		for id in saved[city]:
			if not id is String or not saved[city][id] is Dictionary: continue
			var row: Dictionary = saved[city][id]
			var clean := {}
			for field in ["stock","buy_price","sell_price"]:
				var value: Variant = row.get(field)
				if (value is int or value is float) and is_finite(float(value)) and value >= 0: clean[field] = mini(int(value),2000000000)
			if clean.size() == 3:
				for field in ["buy_price","sell_price","base_buy","base_sell","buy_delta","sell_delta"]:
					var value: Variant = row.get(field)
					if (value is int or value is float) and is_finite(float(value)): clean[field] = float(value)
				if not ["base_buy","base_sell","buy_delta","sell_delta"].all(func(field: String) -> bool: return clean.has(field)):
					clean.erase("base_buy")
				records[id] = clean
		if not records.is_empty(): result[city] = records
	return result

# Reconstructed from original price/init routines 004794d0 and 00479870.
# buy = city selling quote; sell = city buying worth. Keep fractional quotes internally.
static func quotes(row: Dictionary, stock: int) -> Vector2:
	var minimum := float(row.optimal_min_stock)
	var maximum := float(row.optimal_max_stock)
	var band := maximum - minimum - 1.0
	var low := float(row.min_sell_price)
	var high := float(row.max_sell_price)
	var worth_low := float(row.min_worth)
	var worth_high := float(row.max_worth)
	var buy_slope := (low - high) / band if band != 0 else 0.0
	var worth_slope := (worth_low - worth_high) / minimum if minimum != 0 else 0.0
	var buy_at_min := high + buy_slope if low != 0 and high != 0 and minimum != 0 else 0.0
	if stock == minimum: return Vector2(buy_at_min,worth_low)
	var buy := 0.0
	var sell := 0.0
	if stock > minimum:
		if low != 0 and high != 0: buy = low if stock > maximum else (stock - minimum - 1) * buy_slope + high
		if worth_low != 0 and worth_high != 0:
			var intercept := (minimum + 1) * worth_slope + worth_high if band != 0 else 0.0
			var slope := (low * 0.5 - intercept) / band if band != 0 else 0.0
			sell = low * 0.5 if stock > maximum else (stock - minimum - 1) * slope + intercept
	else:
		if worth_low != 0 and worth_high != 0: sell = stock * worth_slope + worth_high
		if low != 0 and high != 0 and minimum != 0 and stock != 0:
			buy = stock * (buy_at_min - worth_high * 5) / minimum + worth_high * 5
	return Vector2(maxf(0,buy),maxf(0,sell))

static func _rows(catalogue: Dictionary) -> Array:
	return catalogue.get("tables",{}).get("economy_commodities",{}).get("records",{}).values()

static func _reset_quote(row: Dictionary, state: Dictionary, project: bool) -> void:
	var price := quotes(row,int(state.stock))
	var next := quotes(row,maxi(0,int(state.stock) + int(row.production_per_hour)))
	state.buy_price = price.x; state.sell_price = price.y
	state.base_buy = price.x; state.base_sell = price.y
	state.buy_delta = next.x - price.x if project and next.x != 0 else 0.0
	state.sell_delta = next.y - price.y if project else 0.0

static func initialize(catalogue: Dictionary, progress: Dictionary) -> void:
	if not progress.has("markets"): progress.markets = {}
	if not progress.has("economy"): progress.economy = {"production_elapsed":0.0,"trader_elapsed":0.0}
	var needs_projection := int(progress.economy.get("quote_version",0)) < 1
	for row in _rows(catalogue):
		var city := str(row.city).to_lower()
		var id := str(row.name).to_lower()
		if not progress.markets.has(city): progress.markets[city] = {}
		if not progress.markets[city].has(id): progress.markets[city][id] = {"stock":maxi(0,int(row.initial_stock))}
		var state: Dictionary = progress.markets[city][id]
		if not state.has("base_buy") or needs_projection: _reset_quote(row,state,true)
	progress.economy.quote_version = 1

static func _production(catalogue: Dictionary, progress: Dictionary) -> void:
	for row in _rows(catalogue):
		var state: Dictionary = progress.markets[str(row.city).to_lower()][str(row.name).to_lower()]
		state.stock = maxi(0,int(state.stock) + int(row.production_per_hour))
		_reset_quote(row,state,true)

# Original traders move one unit at a time, in city/commodity priority order,
# only when a city below its minimum can profit from another city's selling quote.
static func _traders(catalogue: Dictionary, progress: Dictionary) -> void:
	var rows := _rows(catalogue)
	for city in ["touka","velcova","beluga","tryton","factory"]:
		var ordered := rows.filter(func(row: Dictionary) -> bool: return str(row.city).to_lower() == city)
		ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.priority) < int(b.priority))
		for row in ordered:
			var id := str(row.name).to_lower()
			var destination: Dictionary = progress.markets[city][id]
			while int(destination.stock) < int(row.optimal_min_stock):
				var source := {}
				var source_row := {}
				var cheapest := INF
				for candidate in rows:
					if str(candidate.city).to_lower() == city or str(candidate.name).to_lower() != id: continue
					var state: Dictionary = progress.markets[str(candidate.city).to_lower()][id]
					if int(state.stock) > 0 and float(state.buy_price) > 0 and float(state.buy_price) < cheapest:
						cheapest = float(state.buy_price); source = state; source_row = candidate
				if source.is_empty() or cheapest >= float(destination.sell_price): break
				source.stock -= 1; destination.stock += 1
				_reset_quote(source_row,source,true); _reset_quote(row,destination,true)

static func advance(catalogue: Dictionary, progress: Dictionary, delta: float) -> void:
	if not is_finite(delta) or delta <= 0: return
	initialize(catalogue,progress)
	var timing: Dictionary = catalogue.get("tables",{}).get("economy_timing",{}).get("records",{}).get("periods",{})
	var production := maxf(0.1,float(timing.get("production_period",30)))
	var trader := maxf(0.1,float(timing.get("trader_period",150.1)))
	var clock: Dictionary = progress.economy
	var remaining := delta
	while remaining > 0.0000001:
		var step := minf(remaining,minf(production - float(clock.production_elapsed),trader - float(clock.trader_elapsed)))
		clock.production_elapsed += step; clock.trader_elapsed += step; remaining -= step
		if float(clock.production_elapsed) >= production - 0.0000001:
			clock.production_elapsed = 0.0; _production(catalogue,progress)
		if float(clock.trader_elapsed) >= trader - 0.0000001:
			clock.trader_elapsed = 0.0; _traders(catalogue,progress)
	# Preserve the original interpolation gate: fixed buy quotes keep worth fixed too.
	var fraction := float(clock.production_elapsed) / production
	for city in progress.markets.values():
		for state in city.values():
			if float(state.buy_delta) == 0: continue
			if float(state.buy_price) > 10: state.buy_price = float(state.base_buy) + float(state.buy_delta) * fraction
			if float(state.sell_price) > 10: state.sell_price = float(state.base_sell) + float(state.sell_delta) * fraction

static func offers(catalogue: Dictionary, progress: Dictionary, city_id: String) -> Dictionary:
	initialize(catalogue,progress)
	var city := city_key(catalogue,city_id)
	var result := {}
	var tables: Dictionary = catalogue.get("tables",{})
	var texts: Dictionary = tables.get("commodity_text",{}).get("records",{})
	if not progress.has("markets"): progress.markets = {}
	for row in tables.get("economy_commodities",{}).get("records",{}).values():
		if str(row.get("city","")).to_lower() != city: continue
		var id := str(row.get("name","")).to_lower()
		var text: Dictionary = texts.get(row.name,texts.get(id,{}))
		var state: Dictionary = progress.markets[city][id]
		result[id] = {"id":id,"city":city,"name":text.get("Display name",row.name),"description":str(text.get("Description","")).trim_prefix('"').trim_suffix('"'),"info_bitmap":"INTROTEX/" + str(text.get("Info pic","")).to_upper() + ".BMP","stock":state.stock,"buy_price":int(state.buy_price),"sell_price":int(state.sell_price),"source":row}
	return result

static func trade(catalogue: Dictionary, progress: Dictionary, city_id: String, id: String, buying: bool) -> String:
	var offer: Dictionary = offers(catalogue,progress,city_id).get(id,{})
	if offer.is_empty(): return "This station has no market for that commodity."
	var price := int(offer.buy_price if buying else offer.sell_price)
	if price <= 0: return "This station does not trade that commodity in this direction."
	if buying and int(offer.stock) <= 0: return "Out of stock."
	if buying and int(progress.status.credits) < price: return "Not enough credits."
	if not buying and int(progress.cargo.get(id,0)) <= 0: return "No cargo to sell."
	progress.status.credits += -price if buying else price
	progress.cargo[id] = int(progress.cargo.get(id,0)) + (1 if buying else -1)
	if progress.cargo[id] == 0: progress.cargo.erase(id)
	var state: Dictionary = progress.markets[offer.city][id]
	state.stock += -1 if buying else 1
	_reset_quote(offer.source,state,true)
	return ""
