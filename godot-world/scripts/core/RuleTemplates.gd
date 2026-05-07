extends RefCounted
class_name RuleTemplates


static func get_templates() -> Array:
	return [
		{
			"id": "three_d_preview_rule",
			"name": "3D化ルール",
			"description": "GMとの会話で、2Dの主世界を3Dへ切り替えます。",
			"summary": "snapshot.three_d_preview を有効にし、世界の見た目と重力を3Dへ切り替えます。",
			"keywords": ["3d", "3-d", "three d", "three-dimensional", "three dimensional", "3次元", "立体", "3D化", "3d化", "box", "cube"],
			"rule_patch": {
				"id": "rule_three_d_preview",
				"name": "3D化を適用",
				"concept": "three_d_preview",
				"scope": "world",
				"provides_rule_kinds": ["three-d-preview"],
				"install_actions": [
					{
						"op": "merge_world_state",
						"path": "preview_3d",
						"value": {
							"enabled": true,
							"camera": {
								"position": {"x": 8.0, "y": 7.0, "z": 10.0},
								"look_at": {"x": 0.0, "y": 1.1, "z": 0.0},
								"fov_degrees": 55.0
							},
							"lighting": {
								"enabled": false,
								"shadows_enabled": false,
								"light_rotation_degrees": {"x": -55.0, "y": 45.0, "z": 0.0},
								"color": "#fff3c4",
								"intensity": 1.15
							},
							"gravity": {
								"enabled": false,
								"floor_y": 0.0,
								"acceleration": 9.8
							}
						}
					}
				],
				"effects": []
			}
		},
		{
			"id": "three_d_light_rule",
			"name": "3D光ルール",
			"description": "3D表示で影を見せるための光設定を追加します。",
			"summary": "3D化後の世界を前提に、snapshot.three_d_preview.lighting へ影つきの指向性ライトを有効化します。",
			"keywords": ["light", "lighting", "shadow", "sun", "照明", "ライト", "光", "影", "シャドウ"],
			"rule_patch": {
				"id": "rule_three_d_light",
				"name": "3D光を導入",
				"concept": "lighting",
				"scope": "world",
				"requires_rule_kinds": ["three-d-preview"],
				"provides_rule_kinds": ["three-d-lighting", "shadow-lighting"],
				"install_actions": [
					{
						"op": "merge_world_state",
						"path": "preview_3d.lighting",
						"value": {
							"enabled": true,
							"shadows_enabled": true,
							"light_rotation_degrees": {"x": -62.0, "y": 30.0, "z": 0.0},
							"color": "#fff1bf",
							"intensity": 1.35
						}
					}
				],
				"effects": []
			}
		},
		{
			"id": "three_d_gravity_rule",
			"name": "3D重力ルール",
			"description": "3D表示で落下が見えるように、決定論的な重力とデモ物体を追加します。",
			"summary": "3D化後の世界を前提に、重力を有効化し、ステップで落ちる吊り下げ箱を配置します。",
			"keywords": ["gravity", "fall", "falling", "drop", "重力", "落下", "落ちる", "落とす"],
			"rule_patch": {
				"id": "rule_three_d_gravity",
				"name": "3D重力を導入",
				"concept": "gravity",
				"scope": "world",
				"requires_rule_kinds": ["three-d-preview"],
				"provides_rule_kinds": ["gravity-preview"],
				"install_actions": [
					{
						"op": "merge_world_state",
						"path": "preview_3d.gravity",
						"value": {
							"enabled": true,
							"floor_y": 0.0,
							"acceleration": 9.8
						}
					},
					{
						"op": "upsert_entities",
						"entities": [
							{
								"id": "preview_falling_crate",
								"name": "Falling Crate",
								"archetype": "object",
								"tags": ["object", "portable", "gravity_demo"],
								"material": "wood",
								"weight": 8.0,
								"position": {
									"x": 2.5,
									"y": 6.0,
									"z": -2.0,
									"location": "preview_air"
								},
								"state": {
									"condition": "intact",
									"status": "waiting for gravity"
								},
								"render_3d": {
									"kind": "crate",
									"size": {"x": 1.2, "y": 1.2, "z": 1.2},
									"color": "#b67a45"
								},
								"components": {
									"physics": {
										"dynamic": true,
										"grounded": false,
										"gravity_scale": 1.0,
										"floor_offset_y": 0.6,
										"velocity": {"x": 0.0, "y": 0.0, "z": 0.0}
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
			"id": "object_rule",
			"name": "オブジェクトルール",
			"description": "人以外の物体に物理的な属性を持たせます。",
			"summary": "持ち運べる物体と重い物体を配置し、object-base 能力を提供します。",
			"keywords": ["object", "item", "tool", "prop", "kettle", "crate"],
			"rule_patch": {
				"id": "rule_object_base",
				"name": "オブジェクトルールを導入",
				"concept": "objects",
				"scope": "entity",
				"provides_rule_kinds": ["object-base"],
				"install_actions": [
					{
						"op": "upsert_entities",
						"entities": [
							{
								"id": "object_kettle",
								"name": "Campfire Kettle",
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
									"condition": "worn",
									"status": "filled with water"
								}
							},
							{
								"id": "object_grain_crate",
								"name": "Grain Crate",
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
									"reason": "too heavy for one person"
								},
								"state": {
									"condition": "sturdy",
									"status": "sealed"
								}
							}
						]
					}
				],
				"effects": []
			}
		},
		{
			"id": "ownership_rule",
			"name": "所有ルール",
			"description": "object-base があるとき、既存オブジェクトへ所有情報を追加します。",
			"summary": "object-base を前提に、ワールド内の物体へ所有者を割り当てます。",
			"keywords": ["ownership", "owner", "belong", "property", "possess"],
			"rule_patch": {
				"id": "rule_ownership",
				"name": "所有ルールを導入",
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
										"owner_entity_id": "origin_entity",
										"owner_name": "Origin Entity",
										"relationship": "caretaker"
									}
								}
							},
							{
								"id": "object_grain_crate",
								"components": {
									"ownership": {
										"owner_entity_id": "origin_entity",
										"owner_name": "Origin Entity",
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
								"id": "tool_satchel",
								"name": "道具袋",
								"archetype": "object",
								"tags": ["object", "non_person", "portable"],
								"material": "cloth",
								"weight": 1.8,
								"position": {
									"x": 0.8,
									"y": 0.0,
									"z": 0.2,
									"location": "plaza"
								},
								"portability": {
									"portable": true,
									"carry_style": "shoulder"
								},
								"state": {
									"condition": "丈夫",
									"status": "肩掛け"
								}
							},
							{
								"id": "berry_bundle",
								"name": "ベリー束",
								"archetype": "object",
								"tags": ["object", "non_person", "portable", "food"],
								"material": "berries",
								"weight": 0.6,
								"position": {
									"x": 1.6,
									"y": 0.0,
									"z": -0.3,
									"location": "plaza"
								},
								"portability": {
									"portable": true,
									"carry_style": "bundle"
								},
								"state": {
									"condition": "新鮮",
									"status": "採れたて"
								}
							},
							{
								"id": "storehouse",
								"name": "倉庫",
								"archetype": "object",
								"tags": ["object", "non_person", "storage"],
								"material": "wood",
								"weight": 80.0,
								"position": {
									"x": 3.0,
									"y": 0.0,
									"z": -1.3,
									"location": "plaza"
								},
								"portability": {
									"portable": false,
									"reason": "建物のため持ち運べない"
								},
								"state": {
									"condition": "乾燥",
									"status": "在庫あり"
								}
							},
							{
								"id": "water_jar",
								"name": "水瓶",
								"archetype": "object",
								"tags": ["object", "non_person", "portable", "container"],
								"material": "ceramic",
								"weight": 3.2,
								"position": {
									"x": 2.4,
									"y": 0.0,
									"z": -0.5,
									"location": "plaza"
								},
								"portability": {
									"portable": true,
									"carry_style": "two_hands"
								},
								"state": {
									"condition": "密閉済み",
									"status": "半分まで充填"
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
								"id": "tool_satchel",
								"components": {
									"ownership": {
										"owner_entity_id": "player_character",
										"owner_name": "プレイヤー",
										"relationship": "owner"
									}
								}
							},
							{
								"id": "water_jar",
								"components": {
									"ownership": {
										"owner_entity_id": "player_character",
										"owner_name": "プレイヤー",
										"relationship": "owner"
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
			"id": "parent_child_tree",
			"name": "親子ツリールール",
			"description": "ownership-base があるとき、物体の親子関係と配置先を追加します。",
			"summary": "ベリー束 → 道具袋、水瓶 → 倉庫 の親子・配置関係を導入します。",
			"keywords": ["親子", "ツリー", "入れ物", "配置", "container", "parent", "child", "tree"],
			"rule_patch": {
				"id": "rule_parent_child_tree",
				"name": "親子ツリールール",
				"concept": "parent_tree",
				"scope": "entity",
				"requires_rule_kinds": ["ownership-base"],
				"provides_rule_kinds": ["parent-tree"],
				"install_actions": [
					{
						"op": "upsert_entities",
						"entities": [
							{
								"id": "berry_bundle",
								"components": {
									"containment": {
										"container_entity_id": "tool_satchel"
									}
								}
							},
							{
								"id": "water_jar",
								"components": {
									"placement": {
										"location_entity_id": "storehouse"
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
			"name": "空腹",
			"description": "時間とともに増える空腹を追加します。",
			"summary": "mortal エンティティに、毎ステップ増える空腹を追加します。",
			"keywords": ["hunger", "food", "eat", "starve", "starvation"],
			"rule_patch": {
				"id": "rule_hunger",
				"name": "空腹を導入",
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
			"name": "睡眠",
			"description": "休息ルールができるまで溜まる疲労を追加します。",
			"summary": "時間とともに上がる睡眠圧メーターを追加します。",
			"keywords": ["sleep", "rest", "fatigue", "tired", "nap"],
			"rule_patch": {
				"id": "rule_sleep",
				"name": "睡眠を導入",
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
			"name": "体力",
			"description": "あとから他のルールで変えられる体力値を追加します。",
			"summary": "mortal エンティティに持続する体力値を追加します。",
			"keywords": ["health", "hurt", "heal", "wound", "injury"],
			"rule_patch": {
				"id": "rule_health",
				"name": "体力を導入",
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
			"name": "マナ",
			"description": "将来のルールで消費・回復できる魔力を追加します。",
			"summary": "回復可能な魔力資源としてマナを追加します。",
			"keywords": ["mana", "magic", "spell", "arcane", "sorcery"],
			"rule_patch": {
				"id": "rule_mana",
				"name": "マナを導入",
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
