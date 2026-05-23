extends RefCounted
class_name RulePackageUiData

# UI-only display hints layered over rule_package_v1 data.
# package_id / stat_id / tag → 日本語ラベル, アイコン文字, アクセント色。

const PKG_UI := {
	"builtin.health":               {"ja": "体力",           "icon": "♥", "accent": Color("#e07474")},
	"builtin.hunger":               {"ja": "空腹",           "icon": "○", "accent": Color("#e8a464")},
	"builtin.sleep":                {"ja": "睡眠",           "icon": "☾", "accent": Color("#74b3d4")},
	"builtin.time":                 {"ja": "時間",           "icon": "⌚", "accent": Color("#b89bd9")},
	"builtin.mana_absorption":      {"ja": "マナ吸収",       "icon": "✦", "accent": Color("#7ec488")},
	"builtin.peaceful_world_order": {"ja": "平和な世界秩序", "icon": "❀", "accent": Color("#e8c66a")},
	"builtin.default_package":      {"ja": "世界の基盤",     "icon": "◈", "accent": Color("#a8acb7")},
}

const DEFAULT_PKG_UI := {"ja": "", "icon": "▣", "accent": Color("#a8acb7")}

# Package tier labels follow the foundation / bundle / capability split defined
# in `godot-world/docs/rule_packages.md`.
const TIER_JA := {
	"foundation": "基盤",
	"bundle":     "プリセット",
	"capability": "機能パッケージ",
}

const TIER_ACCENT := {
	"foundation": Color("#a8acb7"),
	"bundle":     Color("#e8c66a"),
	"capability": Color("#7ec488"),
}

const STAT_JA := {
	"health": "体力",
	"hunger": "空腹",
	"energy": "エネルギー",
	"elapsed_seconds": "経過秒",
	"mana": "マナ",
}

const TAG_JA := {
	"combat": "戦闘",
	"survival": "生存",
	"health": "体力",
	"damage": "ダメージ",
	"needs": "ニーズ",
	"food": "食事",
	"hunger": "空腹",
	"sleep": "睡眠",
	"energy": "エネルギー",
	"time": "時間",
	"clock": "時計",
	"progression": "進行",
	"magic": "魔法",
	"mana": "マナ",
	"resource": "資源",
	"absorption": "吸収",
	"foundation": "基盤",
	"ownership": "所有",
	"peaceful": "平穏",
	"world-order": "世界秩序",
	"objects": "物体",
	"money": "金銭",
	"meal": "食事",
	"body": "体",
	"world": "世界",
	"existence": "存在",
	"space": "空間",
	"movement": "移動",
	"action": "行動",
	"default-package": "基盤",
	"two_d": "2D",
	"three_d": "3D",
}

const EFFECT_GLYPH := {
	"tick":      "↻",
	"event":     "⚡",
	"threshold": "△",
	"state":     "◐",
	"env":       "✦",
	"relation":  "⇆",
}

const EFFECT_COLOR := {
	"tick":      Color("#74b3d4"),
	"event":     Color("#e8a464"),
	"threshold": Color("#e07474"),
	"state":     Color("#b89bd9"),
	"env":       Color("#7ec488"),
	"relation":  Color("#e8c66a"),
}


static func ui_for(package_id: String) -> Dictionary:
	return PKG_UI.get(package_id, DEFAULT_PKG_UI)


static func ja_for_stat(stat_id: String) -> String:
	return STAT_JA.get(stat_id, stat_id)


static func ja_for_tag(tag: String) -> String:
	return TAG_JA.get(tag, tag)


static func ja_for_tier(tier: String) -> String:
	return TIER_JA.get(tier, "")


static func accent_for_tier(tier: String) -> Color:
	return TIER_ACCENT.get(tier, Color("#a8acb7"))


static func glyph_for_effect(kind: String) -> String:
	return EFFECT_GLYPH.get(kind, "·")


static func color_for_effect(kind: String) -> Color:
	return EFFECT_COLOR.get(kind, Color("#a8acb7"))


static func fmt_num(value: Variant) -> String:
	if value is float:
		if is_equal_approx(value, round(value)):
			return "%d" % int(round(value))
		var text := "%.2f" % value
		while text.length() > 1 and text.ends_with("0"):
			text = text.substr(0, text.length() - 1)
		if text.ends_with("."):
			text = text.substr(0, text.length() - 1)
		return text
	if value is int:
		return "%d" % value
	return str(value)


static func signed(value: float) -> String:
	return ("+" if value >= 0 else "") + fmt_num(value)


# Derive (trigger, delta, kind) effect rows from rule_package_v1 patch.operations.
# Mirrors gm-rule-helpers.jsx's derivedEffects / opToEffect.
static func derived_effects(operations: Array) -> Array:
	var effects: Array = []
	for op_variant in operations:
		if not (op_variant is Dictionary):
			continue
		var op: Dictionary = op_variant
		var op_type := String(op.get("op", ""))
		if op_type == "upsert_stat":
			continue
		var effect := _op_to_effect(op)
		if not effect.is_empty():
			effects.append(effect)
	return effects


# Stats declared by upsert_stat ops.
static func derived_stats(operations: Array) -> Array:
	var stats: Array = []
	for op_variant in operations:
		if not (op_variant is Dictionary):
			continue
		var op: Dictionary = op_variant
		if String(op.get("op", "")) != "upsert_stat":
			continue
		stats.append({
			"id": String(op.get("stat_id", "")),
			"label": ja_for_stat(String(op.get("stat_id", ""))),
			"min": op.get("min", 0),
			"max": op.get("max", 0),
			"default": op.get("default", 0),
			"ui_group": op.get("ui_group", ""),
		})
	return stats


static func _op_to_effect(op: Dictionary) -> Dictionary:
	var op_type := String(op.get("op", ""))
	if op_type == "add_event_binding":
		return {
			"trigger": "イベント %s" % String(op.get("event", "")),
			"delta": String(op.get("target_rule", "")),
			"kind": "event",
		}
	if op_type == "add_relation":
		return {
			"trigger": "関係",
			"delta": String(op.get("relation", op.get("binding_id", ""))),
			"kind": "relation",
		}
	if op_type != "upsert_rule":
		return {}
	var rule_type := String(op.get("rule_type", ""))
	match rule_type:
		"tick_delta":
			return {
				"trigger": "%s秒ごと" % fmt_num(op.get("interval_seconds", 0)),
				"delta": "%s %s" % [ja_for_stat(String(op.get("target_stat", ""))), signed(float(op.get("delta", 0)))],
				"kind": "tick",
			}
		"event_delta":
			return {
				"trigger": String(op.get("event", "")),
				"delta": "%s %s" % [ja_for_stat(String(op.get("target_stat", ""))), signed(float(op.get("delta", 0)))],
				"kind": "event",
			}
		"stateful_recovery":
			return {
				"trigger": "%s 中" % String(op.get("active_event", "")),
				"delta": "%s +%s/s" % [ja_for_stat(String(op.get("target_stat", ""))), fmt_num(op.get("delta_per_second", 0))],
				"kind": "state",
			}
		"environment_delta":
			return {
				"trigger": "環境 %s" % String(op.get("environment_key", "")),
				"delta": "%s +%s/pt" % [ja_for_stat(String(op.get("target_stat", ""))), fmt_num(op.get("delta_per_point", 0))],
				"kind": "env",
			}
		"threshold_effect":
			var effects_arr: Array = op.get("effects", []) if op.get("effects", null) is Array else []
			var eff: Dictionary = effects_arr[0] if not effects_arr.is_empty() and effects_arr[0] is Dictionary else {}
			var result := _threshold_effect_text(eff)
			return {
				"trigger": "%s %s %s" % [
					ja_for_stat(String(op.get("watch_stat", ""))),
					String(op.get("comparator", "")),
					fmt_num(op.get("value", 0))
				],
				"delta": result,
				"kind": "threshold",
			}
		_:
			return {}


static func _threshold_effect_text(eff: Dictionary) -> String:
	var effect_type := String(eff.get("effect_type", ""))
	match effect_type:
		"tag_state":
			return "%s = %s" % [String(eff.get("tag", "")), str(eff.get("value", ""))]
		"stat_delta":
			var delta := float(eff.get("delta", 0))
			var interval = eff.get("interval_seconds", null)
			if interval != null:
				return "%s %s/%ss" % [ja_for_stat(String(eff.get("target_stat", ""))), signed(delta), fmt_num(interval)]
			return "%s %s" % [ja_for_stat(String(eff.get("target_stat", ""))), signed(delta)]
		_:
			return effect_type if not effect_type.is_empty() else "?"
