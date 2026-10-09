extends RefCounted
## Completed player actions. Restoring state must not replay these actions.
## Mission rules can subscribe without coupling themselves to menus or physics.
signal session_started(restored: bool)
signal city_docked(city_id: int)
signal delivery_accepted(entity_id: String, city_id: int, commodity: String, quantity: int)
signal deliveries_collected(city_id: int, goods: Dictionary)
signal commodity_traded(city_id: int, commodity: String, quantity: int, credit_delta: int)
signal equipment_activated(equipment_id: String, active: bool)
signal item_used(item_id: String)
