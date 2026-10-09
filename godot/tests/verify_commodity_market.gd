extends SceneTree
const Market = preload("res://commodity_market.gd")
const Progress = preload("res://player_progress.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var folder := preload("res://asset_paths.gd").find_game_folder()
 var catalogue := preload("res://original_game_data.gd").load_catalogue(folder,false)
 var progress := Progress.restore()
 progress.status.credits = 100000
 for city in ["1","2","3","4","6"]:
  var offers := Market.offers(catalogue,progress,city)
  check(offers.size() == 19,"Original 19 commodities at city " + city)
  for offer in offers.values():
   check(offer.stock == offer.source.initial_stock,"Initial original stock")
   check(offer.buy_price >= 0 and offer.sell_price >= 0,"Valid original quote")
 check(Market.offers(catalogue,progress,"5").is_empty(),"Aquatraz has no commodity market")
 var offers := Market.offers(catalogue,progress,"3")
 var item: Dictionary = offers.rore
 var other_stock: int = Market.offers(catalogue,progress,"1").rore.stock
 var credits := int(progress.status.credits)
 check(Market.trade(catalogue,progress,"3","rore",true).is_empty(),"Buy succeeds")
 check(progress.cargo.rore == 1 and progress.status.credits == credits - item.buy_price,"Exactly one unit charged at shown quote")
 var changed: Dictionary = Market.offers(catalogue,progress,"3").rore
 check(changed.stock == item.stock - 1 and changed.buy_price >= item.buy_price,"Buying raises scarcity price")
 check(Market.offers(catalogue,progress,"1").rore.stock == other_stock,"Other city unaffected")
 check(Market.trade(catalogue,progress,"3","rore",false).is_empty(),"Sell succeeds")
 check(not progress.cargo.has("rore") and Market.offers(catalogue,progress,"3").rore.stock == item.stock,"Selling returns stock")
 progress.status.credits = 0
 var before := JSON.stringify(progress)
 check(not Market.trade(catalogue,progress,"3","rore",true).is_empty() and before == JSON.stringify(progress),"Insufficient funds changes nothing")
 progress.status.credits = 100000
 Market.trade(catalogue,progress,"3","rore",true)
 var restored := Progress.restore(JSON.parse_string(JSON.stringify(progress)))
 check(restored.markets.beluga.rore.stock == progress.markets.beluga.rore.stock and is_equal_approx(restored.markets.beluga.rore.buy_price,progress.markets.beluga.rore.buy_price) and restored.cargo == progress.cargo and restored.status == progress.status,"All city stocks, quotes, cargo and credits survive JSON save restore")
 check(Progress.restore().markets.is_empty(),"New game starts fresh markets")
 var exhausted := Progress.restore()
 exhausted.status.credits = 100000000
 var original: Dictionary = Market.offers(catalogue,exhausted,"3").rore
 for unit in range(original.stock): Market.trade(catalogue,exhausted,"3","rore",true)
 var empty: Dictionary = Market.offers(catalogue,exhausted,"3").rore
 check(empty.stock == 0 and empty.buy_price == 0,"Stock exhaustion removes the buy quote")
 check(not Market.trade(catalogue,exhausted,"3","rore",true).is_empty(),"Cannot buy from exhausted stock")
 exhausted.cargo.rore = 1000
 for unit in range(1000): Market.trade(catalogue,exhausted,"3","rore",false)
 var saturated: Dictionary = Market.offers(catalogue,exhausted,"3").rore
 check(saturated.buy_price == original.source.min_sell_price and saturated.sell_price == int(original.source.min_sell_price * 0.5),"Saturation uses original half sell-price worth floor")
 check(Market.restore({"beluga":{"rore":{"stock":-1,"buy_price":2,"sell_price":1}}}).is_empty(),"Invalid saved market rejected")
 # A profitable source supplies a deficient destination one unit at a time.
 var source_row := {"city":"touka","name":"test","initial_stock":20,"optimal_min_stock":5,"optimal_max_stock":10,"min_worth":10,"max_worth":20,"min_sell_price":30,"max_sell_price":40,"priority":1,"production_per_hour":0}
 var destination_row := source_row.duplicate(); destination_row.merge({"city":"beluga","initial_stock":0,"min_worth":100,"max_worth":200,"min_sell_price":300,"max_sell_price":400},true)
 var synthetic := {"tables":{"economy_commodities":{"records":{"a":source_row,"b":destination_row}}}}
 var trading := Progress.restore()
 Market.advance(synthetic,trading,150.1)
 check(trading.markets.beluga.test.stock == 5 and trading.markets.touka.test.stock == 15,"Traders replenish profitable minimum stock and conserve units")
 var cycle := Progress.restore()
 var initial := Market.offers(catalogue,cycle,"3")
 check(initial.caviar.buy_price == 1726 and initial.water.buy_price == 447,"Recovered Beluga starting quotes")
 var startup_cycle := Progress.restore()
 Market.offers(catalogue,startup_cycle,"3")
 Market.advance(catalogue,startup_cycle,5)
 check(Market.offers(catalogue,startup_cycle,"3").caviar.buy_price > initial.caviar.buy_price,"Initial price interpolation starts before the first production tick")
 var old_cycle := Progress.restore()
 Market.offers(catalogue,old_cycle,"3")
 old_cycle.economy.erase("quote_version")
 for city in old_cycle.markets.values():
  for state in city.values(): state.buy_delta = 0.0; state.sell_delta = 0.0
 Market.advance(catalogue,old_cycle,5)
 check(Market.offers(catalogue,old_cycle,"3").caviar.buy_price > initial.caviar.buy_price,"Existing saves with zero startup deltas resume moving immediately")
 Market.advance(catalogue,cycle,30)
 check(cycle.markets.beluga.caviar.stock == 5,"Production consumes original per-tick amount")
 var tick := Market.offers(catalogue,cycle,"3")
 Market.advance(catalogue,cycle,15)
 var midway := Market.offers(catalogue,cycle,"3")
 check(midway.caviar.buy_price > tick.caviar.buy_price,"Prices interpolate between production ticks")
 check(midway.ore.sell_price == tick.ore.sell_price,"Buy-disabled commodity worth remains fixed between ticks")
 var resumed := Progress.restore(JSON.parse_string(JSON.stringify(cycle)))
 Market.advance(catalogue,cycle,120.1); Market.advance(catalogue,resumed,120.1)
 check(is_equal_approx(cycle.markets.beluga.caviar.buy_price,resumed.markets.beluga.caviar.buy_price) and cycle.markets.beluga.caviar.stock == resumed.markets.beluga.caviar.stock,"Saving mid-cycle resumes production and trader timing")
 var chunked := Progress.restore()
 for step in range(1651): Market.advance(catalogue,chunked,0.1)
 check(chunked.markets.beluga.caviar.stock == cycle.markets.beluga.caviar.stock and is_equal_approx(chunked.markets.beluga.caviar.buy_price,cycle.markets.beluga.caviar.buy_price),"Frame size does not change market results")
 var ui := preload("res://dock_interface.gd").new(); root.add_child(ui)
 ui.setup(folder,func() -> Dictionary: return {"race":1,"commodity_offers":Market.offers(catalogue,progress,"3"),"cargo":progress.cargo,"status":progress.status})
 ui.open("goods")
 check(ui.sale_list.item_count == 19,"All commodities appear")
 for row in range(18):
  var event := InputEventJoypadButton.new(); event.button_index = JOY_BUTTON_DPAD_DOWN; event.pressed = true; ui._input(event)
 check(ui.selected_commodity == str(ui.sale_list.get_item_metadata(18)),"Controller reaches last commodity")
 ui.sale_list.item_selected.emit(1)
 check(not ui.info_dialog.visible,"Selecting does not open info")
 ui.selected_commodity = "rore"; ui.rebuild()
 var actions: Array = []
 ui.action_requested.connect(func(action: String, payload: Dictionary) -> void: actions.append([action,payload]))
 ui.layout.get_node("BuyCommodity").pressed.emit()
 check(actions == [["buy_commodity",{"item":"rore"}]],"Buy uses currently selected item")
 ui.layout.get_node("CommodityInfo").pressed.emit()
 check(ui.info_dialog.visible,"Info button opens original description")
 ui.info_dialog.hide()
 ui.sale_list.grab_focus()
 var focused := root.gui_get_focus_owner()
 var selected := ui.selected_commodity
 Market.advance(catalogue,progress,45)
 ui.refresh_market()
 check(root.gui_get_focus_owner() == focused and ui.selected_commodity == selected,"Live market refresh preserves focus and selection")
 await process_frame
 if DisplayServer.get_name() != "headless":
  await process_frame
  root.get_texture().get_image().save_png("res://tests/commodity-preview.png")
 var credit_label := ui.layout.get_node("CommodityCredits") as Label
 check(credit_label.size == Vector2(100,32) and credit_label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER,"Credits fit and centre vertically inside the box")
 ui.queue_free()
 print("Commodity market: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)
