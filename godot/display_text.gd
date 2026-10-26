extends RefCounted
## Display terminology only; original asset names, IDs and saves stay stable.
static var torpedo_words: RegEx

static func weapons(text: String) -> String:
	if torpedo_words == null:
		torpedo_words = RegEx.new(); torpedo_words.compile("(?i)\\b(missiles?|torpedos)\\b")
	var matches := torpedo_words.search_all(text)
	for index in range(matches.size()-1,-1,-1):
		var hit: RegExMatch = matches[index]
		var word := hit.get_string()
		var replacement := "torpedoes" if word.to_lower().ends_with("s") else "torpedo"
		if word == word.to_upper(): replacement = replacement.to_upper()
		elif word[0] == word[0].to_upper(): replacement = replacement.capitalize()
		text = text.substr(0,hit.get_start())+replacement+text.substr(hit.get_end())
	return text
