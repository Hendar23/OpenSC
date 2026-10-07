extends RefCounted
## Import the player's original data in memory. No extracted content is bundled.
const Database = preload("res://scenery_loader.gd")
const Mods = preload("res://mod_registry.gd")
const INPUTS := ["DATA/DATA.ENC","DATA/ENGLISH/LANGUAGE.ENC","DATA/SCEN1.DDB"]
const CSV_TABLES := {"OBJECTS.CSV":"objects","WEAPONS.CSV":"equipment","WEAPONS1.CSV":"equipment_prices.1","WEAPONS3.CSV":"equipment_prices.3","WEAPONS4.CSV":"equipment_prices.4","REWARD1.CSV":"mission_rewards","MISSION1.CSV":"mission_availability"}
static var cached_signature := ""
static var cached_base := {}

static func load_catalogue(folder: String, with_mods: bool = true) -> Dictionary:
	var fingerprints := {}
	for relative in INPUTS:
		var path := folder.path_join(relative)
		fingerprints[relative] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
	var signature := folder + JSON.stringify(fingerprints)
	if signature != cached_signature:
		cached_base = _import(folder,fingerprints)
		cached_signature = signature
	var result := cached_base.duplicate(true)
	if with_mods:
		Mods.ensure()
		result.provenance["mods"] = []
		var candidates := Mods.candidates("data.gameplay"); candidates.reverse()
		for entry in candidates:
			var patch: Variant = JSON.parse_string(FileAccess.get_file_as_string(entry.path))
			var errors := apply_patch(result,patch)
			if errors.is_empty(): result.provenance.mods.append(entry.pack)
			for error in errors: Mods.note("%s gameplay data: %s" % [entry.name,error])
	return result

static func _import(folder: String, fingerprints: Dictionary) -> Dictionary:
	var result := {"schema_version":1,"provenance":{"importer_version":1,"files":fingerprints},"tables":{},"warnings":[]}
	for relative in INPUTS:
		if fingerprints[relative] == "missing": result.warnings.append("Missing original file: " + relative)
	var archive := read_archive(folder.path_join(INPUTS[0]))
	var language := read_archive(folder.path_join(INPUTS[1]))
	if archive.is_empty(): result.warnings.append("No gameplay archive could be decoded.")
	if language.is_empty(): result.warnings.append("No English language archive could be decoded.")
	var texts := {"source":"Original archives","records":{}}
	for bundle in [{"files":archive,"source":INPUTS[0]},{"files":language,"source":INPUTS[1]}]:
		for name in bundle.files:
			texts.records[("data." if bundle.source == INPUTS[0] else "english.") + name.to_lower()] = {"text":bundle.files[name],"source":bundle.source + ":" + name}
	result.tables["source_texts"] = texts
	for name in CSV_TABLES:
		if archive.has(name): result.tables[CSV_TABLES[name]] = _csv_table(archive[name],INPUTS[0] + ":" + name)
	if archive.has("TRADEDAT.CSV"): _trade_tables(result.tables,archive["TRADEDAT.CSV"])
	for name in ["REQUIRE.TXT","ROUTES.TXT"]:
		if archive.has(name): result.tables["mission_requirements" if name == "REQUIRE.TXT" else "mission_routes"] = _lists(archive[name],name)
	if archive.has("MISSORD.CSV"):
		var records := {}; var stage := ""
		for row in csv_rows(archive["MISSORD.CSV"]):
			if row.is_empty(): continue
			if row[0] == "#stage":
				stage = str(row[1]); records[stage] = {"parameters":row.slice(2),"core":[],"optional":[]}
			elif not stage.is_empty() and row[0] in ["#core","#miss"]:
				records[stage]["core" if row[0] == "#core" else "optional"].append(row.slice(1))
		result.tables["campaign_stages"] = {"source":"DATA/DATA.ENC:MISSORD.CSV","records":records}
	for name in ["WEAPTXT.CSV","TRADETXT.CSV"]:
		if language.has(name): result.tables["equipment_text" if name == "WEAPTXT.CSV" else "commodity_text"] = _csv_table(language[name],INPUTS[1] + ":" + name)
	if language.has("ENGLISH.TXT"): result.tables["mission_text"] = _mission_text(language["ENGLISH.TXT"])
	var file := FileAccess.open(folder.path_join(INPUTS[2]),FileAccess.READ)
	var tables := Database.decode_database(file.get_buffer(file.get_length()),true) if file != null else {}
	if tables.is_empty(): result.warnings.append("No scenery/mission database could be decoded.")
	for name in tables:
		var records := {}
		for row in tables[name]:
			if row.get("matrix") is Array:
				var matrix: Array = []
				for lane in range(row.matrix.size()): matrix.append(null if lane % 4 == 3 else row.matrix[lane])
				row.matrix = matrix
			var id := str(row.get("MissionID",row.get("StoryID",row.get("CityID",row.get("name",row.index)))))
			if name == "Objects": id = str(row.index)
			if name == "Missions": id += "." + str(row.get("StoryID",0))
			_put(records,id,row)
		var table_id: String = "object_types" if name == "objects" else name.to_lower()
		result.tables["database." + table_id] = {"source":INPUTS[2] + ":" + name,"records":records}
	# These are provisional OpenSC combat rules, not recovered executable code.
	_import_city_radio(result,language)
	_import_city_descriptions(result,language)
	result.tables["weapon_tuning"] = {"source":"OpenSC provisional combat defaults","records":{"zapper":preload("res://submarine_weapons.gd").DEFAULTS.duplicate()}}
	var stats := {}
	for record in result.tables.get("objects",{}).get("records",{}).values():
		var model := str(record.get("dff","none")).to_lower()
		if model != "none" and not stats.has(model) and float(record.get("shield",0)) > 0:
			stats[model] = {"health":float(record.shield),"source_object":record.id}
	result.tables["creature_stats"] = {"source":"Original object shield values used as provisional creature health","records":stats}
	return result

static func _import_city_radio(catalogue: Dictionary, language: Dictionary) -> void:
	var messages := {}
	for line in str(language.get("MESSAGES.TXT","")).split("\n"):
		var fields := line.split("\t")
		if fields.size() >= 5: messages[fields[0].strip_edges()] = {"text":fields[4].strip_edges()}
	catalogue.tables["radio_messages"] = {"source":"DATA/ENGLISH/LANGUAGE.ENC:MESSAGES.TXT","records":messages}
	var places: Array[Dictionary] = []
	for line in str(language.get("PLACES.TXT","")).split("\n"):
		var fields := line.strip_edges().split("\t")
		if fields.size() < 6: continue
		places.append({"name":str(fields[1]).replace("_"," ").capitalize(),"radius":float(fields[5])})
	var records := {}
	# Relay groups follow language-message order; dock IDs follow SCEN1.DDB.
	var codes := {1:1,2:7,3:4,4:10,5:13,6:16}
	for row in catalogue.tables.get("database.cities",{}).get("records",{}).values():
		var id := int(row.CityID)
		if not codes.has(id): continue
		var code: int = codes[id]
		var greeting := str(messages.get("city%d" % code,{}).get("text",""))
		for place in places:
			if not greeting.to_lower().contains(str(place.name).to_lower()): continue
			records[str(id)] = {"name":place.name,"legacy_name":str(row.CityName).strip_edges(),"greeting_radius":place.radius,"greeting_neutral":"city%d" % code,"greeting_hostile":"city%d" % (code + 1),"greeting_friendly":"city%d" % (code + 2)}
			break
	catalogue.tables["city_info"] = {"source":"Original city database, relay messages and place names","records":records}

static func apply_city_names(world: Node, catalogue: Dictionary) -> void:
	var records: Dictionary = catalogue.get("tables",{}).get("city_info",{}).get("records",{})
	for node in world.find_children("*","Node3D",true,false):
		if not node.has_meta("city_id"): continue
		var record: Dictionary = records.get(str(int(node.get_meta("city_id"))),{})
		if record.is_empty(): continue
		var current := str(node.get_meta("city_name",""))
		# Preserve explicitly authored map names, including custom added docks.
		if current == str(record.get("legacy_name","")) or current.is_empty():
			node.set_meta("city_name",str(record.name))

static func _import_city_descriptions(catalogue: Dictionary, language: Dictionary) -> void:
	var records := {}
	var cities: Array[String] = []
	var standings: Array[String] = []
	var lines: Array[String] = []
	for raw in (str(language.get("CITY.TXT","")) + "\n#end").split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.to_lower().begins_with("#rem"): continue
		if line.begins_with("#") or line.begins_with("@"):
			if not lines.is_empty():
				var spaces := RegEx.new(); spaces.compile("\\s+")
				var text := spaces.sub(" ".join(lines)," ",true).replace(" <p> ","\n").replace("<p> ","\n").strip_edges()
				# Consecutive paragraph markers retain the original blank lines.
				text = text.replace("<p>","\n").replace("\n ","\n")
				for city in cities:
					for standing in standings: records[city + "." + standing] = {"text":text}
				lines.clear(); standings.clear()
				if line.begins_with("#"): cities.clear()
			if line.begins_with("#"): cities.append(line.substr(1).to_lower())
			else: standings.append(line.substr(1).to_lower())
		else: lines.append(line)
	catalogue.tables["city_descriptions"] = {"source":"DATA/ENGLISH/LANGUAGE.ENC:CITY.TXT","records":records}
	var names := {"1":["touka","N-TOU"],"2":["velcova","N-VEL"],"3":["beluga","N-BEL"],"4":["tryton","N-TRY"],"5":["aquatraz","N-AQU"],"6":["refinery","N-REF"]}
	for id in names:
		if not catalogue.tables.city_info.records.has(id): continue
		catalogue.tables.city_info.records[id]["description_key"] = names[id][0]
		catalogue.tables.city_info.records[id]["title_bitmap"] = "INTROTEX/" + names[id][1] + ".BMP"

static func read_archive(path: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return {}
	var bytes := file.get_buffer(file.get_length())
	if bytes.size() < 4: return {}
	var count := int(bytes.decode_u32(0)); var base := 4 + count * 21
	if count > 256 or base > bytes.size(): return {}
	var result := {}
	for index in range(count):
		var offset := 4 + index * 21
		var name := Database._string(bytes,offset,13)
		var size := int(bytes.decode_u32(offset + 13)); var start := base + int(bytes.decode_u32(offset + 17))
		if size > bytes.size() or start > bytes.size() - size: return {}
		var text := bytes.slice(start,start + size)
		for byte in range(text.size()): text[byte] ^= 255
		var terminator := text.find(0)
		if terminator >= 0: text.resize(terminator)
		result[name.to_upper()] = text.get_string_from_ascii().replace("\r","")
	return result

static func csv_rows(text: String) -> Array:
	var rows := []; var row := []; var field := ""; var quoted := false; var offset := 0
	while offset < text.length():
		var character := text[offset]
		if character == "\"":
			if quoted and offset + 1 < text.length() and text[offset + 1] == "\"": field += "\""; offset += 1
			else: quoted = not quoted
		elif not quoted and character in [",","\n"]:
			row.append(field.strip_edges()); field = ""
			if character == "\n":
				if row.any(func(value: String) -> bool: return not value.is_empty()): rows.append(row)
				row = []
		elif character != "\r": field += character
		offset += 1
	if not field.is_empty() or not row.is_empty(): row.append(field.strip_edges()); rows.append(row)
	return rows

static func _value(text: String) -> Variant:
	if text.is_valid_int(): return text.to_int()
	if text.is_valid_float() and is_finite(text.to_float()): return text.to_float()
	return text

static func _csv_table(text: String, source: String) -> Dictionary:
	var rows := csv_rows(text); var records := {}; var columns: Array = rows[0] if not rows.is_empty() else []
	for row in rows.slice(1):
		if row.is_empty() or row[0].begins_with("#rem"): continue
		var values: Array = row.slice(1) if row[0] == "#name" else row
		var headers: Array = columns.slice(1) if row[0] == "#name" else columns
		var entry := {}
		for index in range(values.size()):
			var label := str(headers[index]) if index < headers.size() else "extra_%d" % index
			if index == 0: label = "id"
			entry[label] = _value(values[index])
		_put(records,str(values[0]),entry)
	return {"source":source,"columns":columns,"records":records}

static func _put(records: Dictionary, name: String, entry: Dictionary) -> void:
	var base := name.strip_edges().to_lower(); var id := base; var occurrence := 2
	while records.has(id): id = base + "~%d" % occurrence; occurrence += 1
	records[id] = entry

static func _trade_tables(tables: Dictionary, text: String) -> void:
	var cities := {}; var goods := {}; var periods := {}; var city := ""
	var fields := ["name","initial_stock","production_per_hour","optimal_min_stock","optimal_max_stock","min_worth","max_worth","min_sell_price","max_sell_price","priority"]
	for row in csv_rows(text):
		if row[0] == "#periodtime" and row.size() >= 3: periods = {"trader_period":_value(row[1]),"production_period":_value(row[2])}
		elif row[0] == "#city" and row.size() >= 5:
			city = row[1].to_lower(); cities[city] = {"name":row[1],"initial_cash":_value(row[2]),"cash_inflow_per_day":_value(row[3]),"goods_per_trader":_value(row[4])}
		elif row[0] == "#commodity" and not city.is_empty() and row.size() >= 11:
			var entry := {"city":city}
			for index in range(fields.size()): entry[fields[index]] = _value(row[index + 1])
			goods[city + "." + row[1].to_lower()] = entry
	for pair in [["economy_cities",cities],["economy_commodities",goods],["economy_timing",{"periods":periods}]]:
		tables[pair[0]] = {"source":"DATA/DATA.ENC:TRADEDAT.CSV","records":pair[1]}

static func _lists(text: String, name: String) -> Dictionary:
	var records := {}
	for line in text.split("\n",false):
		var parts: Array[String] = []
		for part in line.replace("\t"," ").split(" ",false): parts.append(part)
		if not parts.is_empty(): _put(records,parts[0],{"items":parts.slice(1)})
	return {"source":"DATA/DATA.ENC:" + name,"records":records}

static func _mission_text(text: String) -> Dictionary:
	var records := {}; var id := ""; var section := ""
	for line in text.split("\n"):
		if line.begins_with("#mission "):
			if not id.is_empty(): _put(records,id,{"text":section})
			id = line.trim_prefix("#mission ").strip_edges(); section = ""
		elif not id.is_empty(): section += line + "\n"
	if not id.is_empty(): _put(records,id,{"text":section})
	return {"source":"DATA/ENGLISH/LANGUAGE.ENC:ENGLISH.TXT","records":records}

static func apply_patch(catalogue: Dictionary, patch: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not patch is Dictionary or patch.get("schema_version") != 1 or not patch.get("tables") is Dictionary:
		errors.append("Expected schema_version 1 and a tables object."); return errors
	# Validate the entire patch before making any changes.
	for table in patch.tables:
		var definition: Variant = patch.tables[table]
		if not definition is Dictionary or not definition.get("records") is Dictionary:
			errors.append("Table %s must contain a records object." % table); continue
		for id in definition.records:
			var record: Variant = definition.records[id]
			if not record is Dictionary and record != null: errors.append("Record %s/%s must be an object or null." % [table,id])
	if not errors.is_empty(): return errors
	for table in patch.tables:
		if not catalogue.tables.has(table): catalogue.tables[table] = {"source":"mod","records":{}}
		var records: Dictionary = catalogue.tables[table].records
		for id in patch.tables[table].records:
			var record: Variant = patch.tables[table].records[id]
			if record == null: records.erase(id)
			else:
				if not records.has(id): records[id] = {}
				records[id].merge(record.duplicate(true),true)
	return errors

static func export_catalogue(catalogue: Dictionary, path: String) -> Error:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(catalogue,"\t",true))
	return OK
