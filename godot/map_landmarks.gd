extends RefCounted
## Original PLACES.TXT labels, using the same proximity reveal as city names.
const CITIES := ["Touka","Beluga","Velcova","Tryton","Aquatraz","Refinery"]
var markers: Array[Dictionary] = []
var visited := {}

func setup(catalogue: Dictionary) -> void:
	markers.clear(); reset()
	var tables: Dictionary = catalogue.get("tables",{})
	var text: String = tables.get("source_texts",{}).get("records",{}).get("english.places.txt",{}).get("text","")
	var whitespace := RegEx.new(); whitespace.compile("\\s+")
	for raw in text.split("\n",false):
		var fields := whitespace.sub(raw.strip_edges()," ",true).split(" ",false)
		if fields.size() != 6 or fields[0] in CITIES: continue
		if not [fields[2],fields[3],fields[4],fields[5]].all(func(value: String) -> bool: return value.is_valid_float() and is_finite(float(value))): continue
		if float(fields[5]) <= 0: continue
		# PLACES coordinates are already in BSP space, unlike DDB matrices.
		markers.append({"id":str(fields[0]),"name":str(fields[1]).replace("_","\n"),"position":Vector3(float(fields[2]),float(fields[3]),float(fields[4])),"radius":float(fields[5])})

func reset() -> void:
	visited.clear()

func discover(point: Vector3, discovery_range: float) -> void:
	for marker in markers:
		if Vector2(point.x-marker.position.x,point.z-marker.position.z).length() <= discovery_range:
			visited[marker.id] = true

func known(marker: Dictionary) -> bool:
	return visited.has(marker.id)

func reveal_all() -> void:
	for marker in markers: visited[marker.id] = true

func snapshot() -> Dictionary:
	var seen := visited.keys(); seen.sort()
	return {"visited":seen}

static func valid_snapshot(value: Variant) -> bool:
	if not value is Dictionary: return false
	for field in ["visited","enabled"]:
		if field == "enabled" and not value.has(field): continue
		if not value.get(field) is Array or value[field].size() > 256: return false
		for id in value[field]:
			if not id is String or id.is_empty() or id.length() > 128: return false
	return true

func restore(saved: Dictionary, map: RefCounted) -> void:
	reset()
	if not saved.is_empty():
		for marker in markers:
			if saved.get("visited",[]).has(marker.id): visited[marker.id] = true
	else:
		# Published betas only saved exploration. Recover previously explored
		# locations without requiring a revisit or a mission-route name.
		for marker in markers:
			if map.is_explored(marker.position): visited[marker.id] = true
