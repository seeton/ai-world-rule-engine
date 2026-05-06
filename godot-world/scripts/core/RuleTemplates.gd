extends RefCounted
class_name RuleTemplates


static func get_templates() -> Array:
	return [
		{
			"id": "world_time",
			"name": "世界時刻",
			"description": "世界に時間の概念を追加します。時刻が経過するにつれて秒とターンが進みます。",
			"summary": "決定論的な時間システムを追加",
			"keywords": ["時間", "時刻", "クロック", "タイム", "ルール", "作成", "時間のルール"],
			"rule_patch": {
				"id": "rule_world_time",
				"name": "世界時刻ルール",
				"concept": "time",
				"scope": "world",
				"target_tags": [],
				"effects": [
					{
						"component": "world_clock",
						"field": "elapsed_seconds",
						"op": "add",
						"default": 0.0,
						"value_per_second": 1.0,
						"min": 0.0,
						"max": 999999999.0
					},
					{
						"component": "world_clock",
						"field": "total_ticks",
						"op": "add",
						"default": 0.0,
						"value_per_second": 0.0,
						"min": 0.0,
						"max": 999999999.0
					}
				]
			}
		},
		{
			"id": "object_base",
			"name": "オブジェクトルール",
			"description": "物体エンティティを追加し、object-base 親種別を提供します。",
			"summary": "持ち運べる物体と重い物体を配置し、オブジェクト系ルールの土台を作ります。",
			"keywords": ["オブジェクト", "物体", "アイテム", "道具", "object", "item", "tool", "crate"],
			"rule_patch": {
				"id": "rule_object_base",
				"name": "オブジェクト基礎ルール",
				"concept": "objects",
				"scope": "entity",
				"provides_rule_kinds": ["object-base"],
				"install_actions": [
					{
						"op": "upsert_entities",
						"entities": [
							{
								"id": "object_kettle",
								"name": "湯沸かしケトル",
								"archetype": "object",
								"tags": ["object", "non_person", "portable"],
								"material": "iron",
								"weight": 2.5,
								"position": {
									"x": 2.0,
									"y": 0.0,
									"z": 1.0,
									"location": "campfire"
								},
								"portability": {
									"portable": true,
									"carry_style": "handheld"
								},
								"state": {
									"condition": "使い込み",
									"status": "水入り"
								}
							},
							{
								"id": "object_grain_crate",
								"name": "穀物箱",
								"archetype": "object",
								"tags": ["object", "non_person", "storage"],
								"material": "wood",
								"weight": 18.0,
								"position": {
									"x": -3.0,
									"y": 0.0,
									"z": 4.0,
									"location": "storehouse"
								},
								"portability": {
									"portable": false,
									"reason": "一人では重すぎる"
								},
								"state": {
									"condition": "頑丈",
									"status": "封印済み"
								}
							}
						]
					}
				],
				"effects": []
			}
		},
		{
			"id": "ownership_links",
			"name": "所有ルール",
			"description": "object-base があるとき、既存の物体へ所有情報を追加します。",
			"summary": "object-base を前提に、ワールド内の物体へ所有者を割り当てます。",
			"keywords": ["所有", "所有者", "持ち主", "ownership", "owner", "belong"],
			"rule_patch": {
				"id": "rule_ownership_links",
				"name": "所有関係ルール",
				"concept": "ownership",
				"scope": "entity",
				"requires_rule_kinds": ["object-base"],
				"provides_rule_kinds": ["ownership-base"],
				"install_actions": [
					{
						"op": "upsert_entities",
						"entities": [
							{
								"id": "object_kettle",
								"components": {
									"ownership": {
										"owner_entity_id": "player_character",
										"owner_name": "プレイヤー",
										"relationship": "caretaker"
									}
								}
							},
							{
								"id": "object_grain_crate",
								"components": {
									"ownership": {
										"owner_entity_id": "player_character",
										"owner_name": "プレイヤー",
										"relationship": "quartermaster"
									}
								}
							}
						]
					}
				],
				"effects": []
			}
		},
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
