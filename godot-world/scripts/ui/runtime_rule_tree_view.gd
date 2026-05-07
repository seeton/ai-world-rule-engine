class_name RuntimeRuleTreeView
extends RefCounted


static func populate(tree: Tree, rule_tree: Dictionary) -> int:
	if tree == null:
		return 0

	tree.clear()
	var root_item := tree.create_item()
	var roots := _normalize_node_array(rule_tree.get("roots", []))
	var nodes_by_rule_id := _coerce_dictionary(rule_tree.get("nodes_by_rule_id", {}))
	var displayed_rule_ids: Dictionary = {}

	if roots.is_empty() and nodes_by_rule_id.is_empty():
		var empty_item := tree.create_item(root_item)
		empty_item.set_text(0, "導入済みルールなし")
		empty_item.set_text(1, "まだ表示できるルールツリーがありません。")
		return 0

	for root_node in roots:
		_add_rule_tree_item(tree, root_item, root_node, nodes_by_rule_id, [], displayed_rule_ids)

	var undisplayed_rule_ids: Array = []
	var all_rule_ids: Array = nodes_by_rule_id.keys()
	all_rule_ids.sort()
	for rule_id_variant in all_rule_ids:
		var rule_id := str(rule_id_variant)
		if not displayed_rule_ids.has(rule_id):
			undisplayed_rule_ids.append(rule_id)

	if not undisplayed_rule_ids.is_empty():
		var overflow_group := tree.create_item(root_item)
		overflow_group.set_text(0, "追加の連結ルール")
		overflow_group.set_text(1, "親リンク待ち / 循環候補")
		for rule_id in undisplayed_rule_ids:
			var overflow_node := _coerce_dictionary(nodes_by_rule_id.get(rule_id, {}))
			if overflow_node.is_empty():
				overflow_node = {"rule_id": rule_id, "name": rule_id}
			_add_rule_tree_item(tree, overflow_group, overflow_node, nodes_by_rule_id, [], displayed_rule_ids)

	return displayed_rule_ids.size()


static func _add_rule_tree_item(
	tree: Tree,
	parent_item: TreeItem,
	rule_node: Dictionary,
	nodes_by_rule_id: Dictionary,
	ancestry: Array,
	displayed_rule_ids: Dictionary
) -> void:
	var merged_node := _merge_rule_node(rule_node, nodes_by_rule_id)
	var rule_id := str(merged_node.get("rule_id", ""))
	if rule_id.is_empty():
		return

	if ancestry.has(rule_id):
		var cycle_item := tree.create_item(parent_item)
		cycle_item.set_text(0, "循環を検出")
		cycle_item.set_text(1, rule_id)
		return

	var rule_item := tree.create_item(parent_item)
	rule_item.set_text(0, _format_rule_label(merged_node))
	rule_item.set_text(1, _summarize_rule_status(merged_node, nodes_by_rule_id))
	rule_item.set_metadata(0, rule_id)
	displayed_rule_ids[rule_id] = true

	var resolved_parent_ids := _normalize_string_array(merged_node.get("resolved_parent_rule_ids", []))
	if resolved_parent_ids.size() > 1:
		var extra_parent_item := tree.create_item(rule_item)
		extra_parent_item.set_text(0, "別の親にも接続")
		extra_parent_item.set_text(1, _format_rule_reference_list(
			resolved_parent_ids.slice(1, resolved_parent_ids.size()),
			nodes_by_rule_id
		))

	for required_kind in _get_unresolved_required_kinds(merged_node, nodes_by_rule_id):
		var unresolved_item := tree.create_item(rule_item)
		unresolved_item.set_text(0, "必要な親種別")
		var candidate_ids := _find_provider_ids(str(required_kind), nodes_by_rule_id)
		if candidate_ids.is_empty():
			unresolved_item.set_text(1, str(required_kind))
		else:
			unresolved_item.set_text(1, "%s (候補: %s)" % [
				str(required_kind),
				_format_rule_reference_list(candidate_ids, nodes_by_rule_id)
			])

	var next_ancestry := ancestry.duplicate()
	next_ancestry.append(rule_id)
	for child_node in _normalize_node_array(merged_node.get("children", [])):
		_add_rule_tree_item(tree, rule_item, child_node, nodes_by_rule_id, next_ancestry, displayed_rule_ids)


static func _merge_rule_node(rule_node: Dictionary, nodes_by_rule_id: Dictionary) -> Dictionary:
	var merged_node := _coerce_dictionary(nodes_by_rule_id.get(str(rule_node.get("rule_id", "")), {})).duplicate(true)
	for key in rule_node.keys():
		merged_node[key] = rule_node[key]
	return merged_node


static func _summarize_rule_status(rule_node: Dictionary, nodes_by_rule_id: Dictionary) -> String:
	var parts: Array[String] = []
	var resolved_parent_ids := _normalize_string_array(rule_node.get("resolved_parent_rule_ids", []))
	if resolved_parent_ids.is_empty():
		parts.append("根ルール" if _get_unresolved_required_kinds(rule_node, nodes_by_rule_id).is_empty() else "親リンク待ち")
	else:
		parts.append("親: %s" % _format_rule_reference_list(resolved_parent_ids, nodes_by_rule_id))

	var child_rule_ids := _normalize_string_array(rule_node.get("child_rule_ids", []))
	if not child_rule_ids.is_empty():
		parts.append("子ルール %d 件" % child_rule_ids.size())

	var provided_kinds := _normalize_string_array(rule_node.get("provides_rule_kinds", []))
	if not provided_kinds.is_empty():
		parts.append("提供: %s" % _join_values(provided_kinds))

	var unresolved_required_kinds := _get_unresolved_required_kinds(rule_node, nodes_by_rule_id)
	if not unresolved_required_kinds.is_empty():
		parts.append("必要: %s" % _join_values(unresolved_required_kinds))

	return _join_values(parts) if not parts.is_empty() else "依存メタデータなし"


static func _get_unresolved_required_kinds(rule_node: Dictionary, nodes_by_rule_id: Dictionary) -> Array:
	var unresolved_required_kinds: Array = []
	var required_kinds := _normalize_string_array(rule_node.get("requires_rule_kinds", []))
	var resolved_parent_ids := _normalize_string_array(rule_node.get("resolved_parent_rule_ids", []))

	for required_kind in required_kinds:
		var is_resolved := false
		for parent_rule_id in resolved_parent_ids:
			var parent_node := _coerce_dictionary(nodes_by_rule_id.get(parent_rule_id, {}))
			var provided_kinds := _normalize_string_array(parent_node.get("provides_rule_kinds", []))
			if provided_kinds.has(required_kind):
				is_resolved = true
				break
		if not is_resolved and not unresolved_required_kinds.has(required_kind):
			unresolved_required_kinds.append(required_kind)

	return unresolved_required_kinds


static func _find_provider_ids(required_kind: String, nodes_by_rule_id: Dictionary) -> Array:
	var provider_ids: Array = []
	var rule_ids: Array = nodes_by_rule_id.keys()
	rule_ids.sort()
	for rule_id_variant in rule_ids:
		var rule_id := str(rule_id_variant)
		var node := _coerce_dictionary(nodes_by_rule_id.get(rule_id, {}))
		if _normalize_string_array(node.get("provides_rule_kinds", [])).has(required_kind):
			provider_ids.append(rule_id)
	return provider_ids


static func _format_rule_reference_list(rule_ids: Array, nodes_by_rule_id: Dictionary) -> String:
	var labels: Array = []
	for rule_id in rule_ids:
		var rule_key := str(rule_id)
		var node := _coerce_dictionary(nodes_by_rule_id.get(rule_key, {}))
		if node.is_empty():
			labels.append(rule_key)
		else:
			labels.append(_format_rule_label(node))
	return _join_values(labels)


static func _format_rule_label(rule_node: Dictionary) -> String:
	var rule_id := str(rule_node.get("rule_id", rule_node.get("id", rule_node.get("name", "rule"))))
	var rule_name := str(rule_node.get("name", rule_id))
	return "%s (%s)" % [rule_name, rule_id]


static func _normalize_node_array(value: Variant) -> Array:
	var nodes: Array = []
	if value is Array:
		for entry in value:
			if entry is Dictionary:
				nodes.append(entry)
	return nodes


static func _normalize_string_array(value: Variant) -> Array:
	var values: Array = []
	if value is Array:
		for entry in value:
			var text := str(entry).strip_edges()
			if not text.is_empty() and not values.has(text):
				values.append(text)
		return values

	var single_value := str(value).strip_edges()
	if not single_value.is_empty() and single_value != "null":
		values.append(single_value)
	return values


static func _join_values(values: Array) -> String:
	var pieces: Array[String] = []
	for value in values:
		pieces.append(str(value))

	var joined := ""
	for index in range(pieces.size()):
		if index > 0:
			joined += ", "
		joined += pieces[index]
	return joined


static func _coerce_dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
