class_name RuleDescriptionFormatter
extends RefCounted

const CONCEPT_LABELS := {
	"action": "基本アクション",
	"body": "身体",
	"existence": "存在",
	"foundation": "世界の土台",
	"health": "体力",
	"hunger": "空腹",
	"mana": "マナ",
	"meal": "食事",
	"money": "お金",
	"movement": "移動",
	"objects": "物や持ち物",
	"ownership": "所有関係",
	"representation": "見た目と表現",
	"sleep": "睡眠と元気",
	"space": "空間と位置",
	"state": "状態の保持",
	"time": "時間の流れ",
	"world_foundation": "世界の土台",
	"world_order": "暮らしの秩序"
}
const FEATURE_LABELS := {
	"action": "基本アクション",
	"base": "基本部分",
	"base_time": "基礎時間",
	"basic_action": "基本アクション",
	"body": "身体",
	"default_package": "基本パッケージ",
	"energy": "元気",
	"existence": "存在",
	"foundation": "世界の土台",
	"health": "体力",
	"hunger": "空腹",
	"meal": "食事",
	"money": "お金",
	"movement": "移動",
	"objects": "物や持ち物",
	"order": "秩序",
	"ownership": "所有関係",
	"peaceful": "平和な暮らし",
	"representation": "見た目と表現",
	"sleep": "睡眠",
	"space": "空間と位置",
	"state": "状態の保持",
	"time": "時間の流れ",
	"world": "世界"
}
const RULE_TYPE_EXPLANATIONS := {
	"environment_delta": "場所や環境に応じて変化させるルールです。",
	"event_delta": "何かが起きたときに変化を起こすルールです。",
	"runtime_rule": "世界の中で常に土台として効くルールです。",
	"stateful_recovery": "休息や回復の流れを扱うルールです。",
	"threshold_effect": "値がしきい値を超えたときに反応するルールです。",
	"tick_delta": "時間が進むたびに少しずつ変化させるルールです。"
}


static func build_tooltip(rule_node: Dictionary, rules_by_id: Dictionary = {}) -> String:
	var normalized := _normalize_rule_node(rule_node)
	var rule_id := String(normalized.get("rule_id", "")).strip_edges()
	if rule_id.is_empty():
		return ""

	var title := _display_title(normalized)
	var lines: Array[String] = [title]

	var summary := _build_human_summary(normalized)
	if not summary.is_empty():
		lines.append("これは何？: %s" % summary)

	var package_label := _format_package_label(normalized)
	if not package_label.is_empty():
		lines.append("どこに入っている？: %s" % package_label)

	var dependency_line := _build_dependency_line(normalized, rules_by_id)
	if not dependency_line.is_empty():
		lines.append("前提: %s" % dependency_line)

	var impact_line := _build_impact_line(normalized)
	if not impact_line.is_empty():
		lines.append("役割: %s" % impact_line)

	lines.append("いまの状態: %s" % _format_status(normalized))

	return "\n".join(lines)


static func _normalize_rule_node(rule_node: Dictionary) -> Dictionary:
	var normalized := rule_node.duplicate(true)
	var metadata := _coerce_dictionary(normalized.get("metadata", {}))
	if not normalized.has("rule_id"):
		normalized["rule_id"] = String(normalized.get("id", ""))
	if not normalized.has("name"):
		normalized["name"] = String(normalized.get("rule_id", normalized.get("id", "rule")))
	if not normalized.has("package_id"):
		normalized["package_id"] = String(metadata.get("package_id", ""))
	if not normalized.has("package_display_name"):
		normalized["package_display_name"] = String(metadata.get("package_display_name", metadata.get("package_id", "")))
	if not normalized.has("package_description"):
		normalized["package_description"] = String(metadata.get("package_description", ""))
	return normalized


static func _display_title(rule_node: Dictionary) -> String:
	var rule_name := String(rule_node.get("name", "")).strip_edges()
	if not rule_name.is_empty():
		return rule_name
	return _describe_focus(rule_node)


static func _build_human_summary(rule_node: Dictionary) -> String:
	var player_description := String(rule_node.get("player_description", "")).strip_edges()
	if not player_description.is_empty():
		return player_description

	var focus := _describe_focus(rule_node)
	var rule_type := String(rule_node.get("rule_type", "")).strip_edges()
	var type_explanation := String(RULE_TYPE_EXPLANATIONS.get(rule_type, "")).strip_edges()
	if not type_explanation.is_empty():
		if rule_type == "runtime_rule":
			return "世界の中で「%s」を成り立たせる、%s" % [focus, type_explanation]
		if rule_type == "tick_delta":
			return "時間経過に合わせて「%s」を動かす、%s" % [focus, type_explanation]
		if rule_type == "event_delta":
			return "出来事に応じて「%s」を変える、%s" % [focus, type_explanation]
		if rule_type == "threshold_effect":
			return "「%s」が危険域や節目に入ったとき反応する、%s" % [focus, type_explanation]
		return "「%s」を扱う、%s" % [focus, type_explanation]
	return "このルールは「%s」を扱うためのルールです。" % focus


static func _build_dependency_line(rule_node: Dictionary, rules_by_id: Dictionary) -> String:
	var resolved_parent_ids := _normalize_string_array(rule_node.get("resolved_parent_rule_ids", []))
	if not resolved_parent_ids.is_empty():
		return "%s を土台にして働きます。" % _format_rule_reference_list(resolved_parent_ids, rules_by_id)

	var unresolved_required_kinds := _normalize_string_array(rule_node.get("unresolved_required_rule_kinds", []))
	if not unresolved_required_kinds.is_empty():
		return "%s がそろうと動き出します。" % _format_feature_list(unresolved_required_kinds)

	var required_kinds := _normalize_string_array(rule_node.get("requires_rule_kinds", []))
	if not required_kinds.is_empty():
		return "%s があると働きます。" % _format_feature_list(required_kinds)

	return "ほかのルールがなくても先に入る土台です。"


static func _build_impact_line(rule_node: Dictionary) -> String:
	var child_rule_ids := _normalize_string_array(rule_node.get("child_rule_ids", []))
	if not child_rule_ids.is_empty():
		return "このルールを土台にするルールが %d 件あります。" % child_rule_ids.size()

	var provided_kinds := _normalize_string_array(rule_node.get("provides_rule_kinds", []))
	if not provided_kinds.is_empty():
		return "%s まわりの仕組みを支えます。" % _format_feature_list(provided_kinds)

	return ""


static func _describe_focus(rule_node: Dictionary) -> String:
	var concept := String(rule_node.get("concept", "")).strip_edges().to_lower()
	if CONCEPT_LABELS.has(concept):
		return String(CONCEPT_LABELS[concept])

	var provided_kinds := _normalize_string_array(rule_node.get("provides_rule_kinds", []))
	if not provided_kinds.is_empty():
		return _format_feature_list(provided_kinds)

	var rule_name := String(rule_node.get("name", "")).strip_edges()
	if not rule_name.is_empty():
		return rule_name

	return _humanize_token(String(rule_node.get("rule_id", "この仕組み")))


static func _format_package_label(rule_node: Dictionary) -> String:
	var package_display_name := String(rule_node.get("package_display_name", "")).strip_edges()
	var package_id := String(rule_node.get("package_id", "")).strip_edges()
	if package_display_name.is_empty():
		return package_id
	if package_id.is_empty() or package_display_name == package_id:
		return package_display_name
	return "%s (%s)" % [package_display_name, package_id]


static func _format_status(rule_node: Dictionary) -> String:
	if bool(rule_node.get("inactive", false)):
		return "いまは無効で、効果を止めています。"
	if bool(rule_node.get("blocked", false)):
		return "条件が足りず停止しています。"
	var unresolved_required_kinds := _normalize_string_array(rule_node.get("unresolved_required_rule_kinds", []))
	if not unresolved_required_kinds.is_empty():
		return "必要な土台が足りず待機中です。"
	var resolved_parent_ids := _normalize_string_array(rule_node.get("resolved_parent_rule_ids", []))
	if resolved_parent_ids.is_empty():
		return "ほかのルールの土台として動いています。"
	var dependency_status := String(rule_node.get("dependency_status", "")).strip_edges()
	if dependency_status == "inactive":
		return "いまは無効で、効果を止めています。"
	if dependency_status == "blocked":
		return "条件が足りず停止しています。"
	return "前提がそろって動いています。"


static func _format_rule_reference_list(rule_ids: Array, rules_by_id: Dictionary) -> String:
	var labels: Array = []
	for rule_id_variant in rule_ids:
		var rule_id := String(rule_id_variant).strip_edges()
		if rule_id.is_empty():
			continue
		var rule_data := _coerce_dictionary(rules_by_id.get(rule_id, {}))
		var rule_name := String(rule_data.get("name", rule_id)).strip_edges()
		labels.append(rule_name if not rule_name.is_empty() else _humanize_token(rule_id))
	return _join_values(labels)


static func _format_feature_list(values: Array) -> String:
	var labels: Array = []
	for value in values:
		var label := _humanize_token(String(value))
		if not label.is_empty() and not labels.has(label):
			labels.append(label)
	return _join_values(labels)


static func _humanize_token(value: String) -> String:
	var text := value.strip_edges()
	if text.is_empty():
		return ""
	var lowered := text.to_lower()
	if CONCEPT_LABELS.has(lowered):
		return String(CONCEPT_LABELS[lowered])

	var normalized := lowered.replace("-", "_").replace(".", "_")
	if FEATURE_LABELS.has(normalized):
		return String(FEATURE_LABELS[normalized])

	var pieces: Array[String] = []
	for segment in normalized.split("_", false):
		if segment.is_empty():
			continue
		if FEATURE_LABELS.has(segment):
			pieces.append(String(FEATURE_LABELS[segment]))
		elif pieces.is_empty():
			pieces.append(text.replace("_", " ").replace(".", " ").replace("-", " "))
			break
	return "・".join(pieces)


static func _normalize_string_array(value: Variant) -> Array:
	var values: Array = []
	if value is Array:
		for entry in value:
			var text := String(entry).strip_edges()
			if not text.is_empty() and not values.has(text):
				values.append(text)
	elif value is PackedStringArray:
		for entry in value:
			var text := String(entry).strip_edges()
			if not text.is_empty() and not values.has(text):
				values.append(text)
	else:
		var single_value := String(value).strip_edges()
		if not single_value.is_empty() and single_value != "null":
			values.append(single_value)
	return values


static func _join_values(values: Array) -> String:
	var pieces: Array[String] = []
	for value in values:
		pieces.append(String(value))
	return ", ".join(pieces)


static func _coerce_dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
