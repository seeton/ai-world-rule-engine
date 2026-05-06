extends RefCounted
class_name RuleTemplates


static func get_templates() -> Array:
	return [
		{
			"id": "three_d_preview_rule",
			"name": "3D Preview Rule",
			"description": "Enables a 3D world preview contract with box-like characters and GM render hints.",
			"summary": "Turns on snapshot.three_d_preview and seeds deterministic 3D metadata for the origin entity plus a GM.",
			"keywords": ["3d", "3-d", "three d", "three-dimensional", "three dimensional", "3次元", "立体", "box", "cube"],
			"rule_patch": {
				"id": "rule_three_d_preview",
				"name": "Install 3D Preview",
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
					},
					{
						"op": "upsert_entities",
						"entities": [
							{
								"id": "origin_entity",
								"position": {
									"x": 0.0,
									"y": 0.9,
									"z": 0.0,
									"location": "preview_center"
								},
								"render_3d": {
									"kind": "character",
									"size": {"x": 0.9, "y": 1.8, "z": 0.9},
									"color": "#5b8cff"
								},
								"components": {
									"physics": {
										"dynamic": false,
										"grounded": true,
										"gravity_scale": 0.0,
										"floor_offset_y": 0.9,
										"velocity": {"x": 0.0, "y": 0.0, "z": 0.0}
									}
								}
							},
							{
								"id": "gm_entity",
								"name": "GM",
								"archetype": "gm",
								"tags": ["character", "gm", "director"],
								"position": {
									"x": -2.5,
									"y": 1.1,
									"z": -1.5,
									"location": "preview_overlook"
								},
								"render_3d": {
									"kind": "gm",
									"size": {"x": 1.1, "y": 2.2, "z": 1.1},
									"color": "#f3c969"
								},
								"components": {
									"behavior": {
										"current_task": "Observing the world preview"
									},
									"physics": {
										"dynamic": false,
										"grounded": true,
										"gravity_scale": 0.0,
										"floor_offset_y": 1.1,
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
			"id": "three_d_light_rule",
			"name": "3D Light Rule",
			"description": "Adds a preview light configuration so shadows can be rendered in the 3D view.",
			"summary": "Requires 3D preview, then enables a directional light with shadows in snapshot.three_d_preview.lighting.",
			"keywords": ["light", "lighting", "shadow", "sun", "照明", "ライト", "光", "影", "シャドウ"],
			"rule_patch": {
				"id": "rule_three_d_light",
				"name": "Install 3D Light",
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
			"name": "3D Gravity Rule",
			"description": "Adds deterministic preview gravity and a falling demo object for the 3D path.",
			"summary": "Requires 3D preview, then enables gravity and seeds a suspended crate that falls over ticks.",
			"keywords": ["gravity", "fall", "falling", "drop", "重力", "落下", "落ちる", "落とす"],
			"rule_patch": {
				"id": "rule_three_d_gravity",
				"name": "Install 3D Gravity",
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
			"name": "Object Rule",
			"description": "Introduces non-person world objects with physical properties.",
			"summary": "Seeds portable and non-portable objects, then provides the object-base capability.",
			"keywords": ["object", "item", "tool", "prop", "kettle", "crate"],
			"rule_patch": {
				"id": "rule_object_base",
				"name": "Install Object Rule",
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
			"name": "Ownership Rule",
			"description": "Adds ownership data to existing objects when an object-base rule is present.",
			"summary": "Requires object-base, then assigns owners to seeded world objects.",
			"keywords": ["ownership", "owner", "belong", "property", "possess"],
			"rule_patch": {
				"id": "rule_ownership",
				"name": "Install Ownership Rule",
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
