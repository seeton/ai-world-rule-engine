extends RefCounted
class_name RuleTemplates


static func get_templates() -> Array:
	return [
		{
			"id": "hunger",
			"name": "Hunger",
			"description": "Introduces hunger as a need that grows over time.",
			"summary": "Adds a hunger need that increases every tick for mortal entities.",
			"keywords": ["hunger", "food", "eat", "starve", "starvation"],
			"rule_patch": {
				"id": "rule_hunger",
				"name": "Install Hunger",
				"concept": "hunger",
				"scope": "entity",
				"target_tags": ["mortal"],
				"effects": [
					{
						"component": "needs",
						"field": "hunger",
						"op": "add",
						"default": 0.0,
						"value_per_second": 0.6,
						"min": 0.0,
						"max": 100.0
					}
				]
			}
		},
		{
			"id": "sleep",
			"name": "Sleep",
			"description": "Introduces fatigue as a need that builds until rest rules exist.",
			"summary": "Adds a sleep pressure meter that climbs over time.",
			"keywords": ["sleep", "rest", "fatigue", "tired", "nap"],
			"rule_patch": {
				"id": "rule_sleep",
				"name": "Install Sleep",
				"concept": "sleep",
				"scope": "entity",
				"target_tags": ["mortal"],
				"effects": [
					{
						"component": "needs",
						"field": "sleep",
						"op": "add",
						"default": 0.0,
						"value_per_second": 0.35,
						"min": 0.0,
						"max": 100.0
					}
				]
			}
		},
		{
			"id": "health",
			"name": "Health",
			"description": "Adds a health stat that other rules can later modify.",
			"summary": "Adds a persistent health stat for mortal entities.",
			"keywords": ["health", "hurt", "heal", "wound", "injury"],
			"rule_patch": {
				"id": "rule_health",
				"name": "Install Health",
				"concept": "health",
				"scope": "entity",
				"target_tags": ["mortal"],
				"effects": [
					{
						"component": "stats",
						"field": "health",
						"op": "add",
						"default": 100.0,
						"value_per_second": 0.0,
						"min": 0.0,
						"max": 100.0
					}
				]
			}
		},
		{
			"id": "mana",
			"name": "Mana",
			"description": "Adds magical energy storage that future rules can spend or refill.",
			"summary": "Adds mana as a refillable magical resource.",
			"keywords": ["mana", "magic", "spell", "arcane", "sorcery"],
			"rule_patch": {
				"id": "rule_mana",
				"name": "Install Mana",
				"concept": "mana",
				"scope": "entity",
				"target_tags": ["mortal"],
				"effects": [
					{
						"component": "stats",
						"field": "mana",
						"op": "add",
						"default": 0.0,
						"value_per_second": 0.05,
						"min": 0.0,
						"max": 100.0
					}
				]
			}
		}
	]
