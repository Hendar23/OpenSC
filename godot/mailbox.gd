extends RefCounted
## Original bulletin mail (SC.EXE 0x449070/0x484040), independent of mission execution.
## Store IDs/read flags, never copies of the player's original language data.
const CITY_GROUPS := {"touka":[1],"beluga":[3],"velcova":[2],"tryton":[4],"factory":[6],"trad":[1,3,5],"tech":[2,4],"global":[1,2,3,4,5,6]}

static func restore(value: Variant) -> Dictionary:
	var result := {"received":{},"outcomes":{},"available":[]}
	if not value is Dictionary: return result
	if value.get("received") is Dictionary:
		for id in value.received:
			var entry: Variant = value.received[id]
			if id is String and id.is_valid_int() and entry is Dictionary and result.received.size() < 99:
				var order: Variant = entry.get("order",result.received.size())
				var read_value: Variant = entry.get("read",false)
				result.received[id] = {"read":read_value is bool and read_value,"order":clampi(int(order),0,999999) if (order is int or order is float) and is_finite(float(order)) else result.received.size()}
	if value.get("outcomes") is Dictionary:
		for id in value.outcomes:
			var score: Variant = value.outcomes[id]
			if id is String and (score is int or score is float) and is_finite(float(score)):
				result.outcomes[id.left(64)] = clampf(float(score),0.0,1.0)
	if value.get("available") is Array:
		for id in value.available:
			if id is String and not result.available.has(id) and result.available.size() < 128: result.available.append(id.left(64))
	return result

static func import_messages(text: String, availability: Array) -> Dictionary:
	var messages := {}; var id := ""; var lines: Array[String] = []
	for raw in (text + "\n#end").split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#") and not line.begins_with("#rem"):
			if not id.is_empty():
				var title: String = lines.pop_front() if not lines.is_empty() else ""
				messages[id] = {"id":id,"subject":title,"body":_paragraphs(lines),"rules":[]}
			id = line.trim_prefix("#bulletin ").strip_edges() if line.begins_with("#bulletin ") else ""
			lines = []
		elif not id.is_empty() and not line.is_empty() and not line.begins_with("#"): lines.append(line)
	for row in availability:
		if row.size() < 6 or not messages.has(str(row[0])): continue
		messages[str(row[0])].rules.append({"cities":CITY_GROUPS.get(str(row[1]),[]),"type":str(row[2]),"dependency":str(row[3]),"low":float(row[4]),"high":float(row[5])})
	return {"source":"Original LANGUAGE.ENC:ENGLISH.TXT bulletins and DATA.ENC:MISSION1.CSV","records":messages}

static func _paragraphs(lines: Array[String]) -> String:
	# Blank source lines are formatting; <p> is the original paragraph delimiter.
	var text := " ".join(lines).replace("<p>","\n")
	while text.contains("\n \n"): text = text.replace("\n \n","\n\n")
	var paragraphs: Array[String] = []
	for paragraph in text.split("\n",false): paragraphs.append(paragraph.strip_edges())
	return "\n\n".join(paragraphs)

static func set_mission_available(progress: Dictionary, id: String, available: bool = true) -> void:
	var state: Dictionary = progress.mail
	if available and not state.available.has(id): state.available.append(id)
	elif not available: state.available.erase(id)

static func mission_completed(progress: Dictionary, id: String, score: float) -> void:
	if not is_finite(score): return
	progress.mail.outcomes[id] = clampf(score,0.0,1.0)
	progress.mail.available.erase(id)

static func messages(catalogue: Dictionary, progress: Dictionary, city: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var state: Dictionary = progress.mail
	for record in catalogue.get("tables",{}).get("mail_messages",{}).get("records",{}).values():
		var eligible := false
		for rule in record.rules:
			if not city in rule.cities: continue
			if rule.type == "pre": eligible = state.available.has(rule.dependency)
			elif rule.type == "post" and int(record.id) >= 1000:
				# 0x4483d0 starts the original stage counter at ZERO; our public
				# campaign_stage starts at one. CSV thresholds use that internal counter.
				var stage := int(progress.get("campaign_stage",1)) - 1
				eligible = stage > int(rule.low) or (stage == int(rule.low) and int(progress.get("campaign_jobs",0)) >= int(rule.high))
			elif rule.type == "post" and state.outcomes.has(rule.dependency):
				var score := float(state.outcomes[rule.dependency])
				eligible = score >= rule.low and (score < rule.high or (score == 1.0 and rule.high == 1.0))
			if eligible: break
		if not eligible: continue
		if not state.received.has(record.id) and state.received.size() < 99: state.received[record.id] = {"read":false,"order":state.received.size()}
		if not state.received.has(record.id): continue
		var message: Dictionary = record.duplicate(true); message.read = state.received[record.id].read
		result.append(message)
	# Original 0x484100 sorts newest arrival first.
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(state.received[a.id].order) > int(state.received[b.id].order))
	return result

static func mark_read(progress: Dictionary, id: String) -> void:
	if progress.mail.received.has(id): progress.mail.received[id].read = true
