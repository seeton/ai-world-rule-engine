extends Node

signal poc_snapshot_changed

const WORLD_2D_SCENE := preload("res://scenes/World2D.tscn")
const WORLD_3D_SCENE := preload("res://scenes/World3D.tscn")
const GM_DIALOG_SCRIPT := preload("res://scripts/ui/gm_dialog.gd")

const DEFAULT_SELECTED_ENTITY_ID := "tool_satchel"
const ACTION_OBJECT_BASE := "install_object_base"
const ACTION_OWNERSHIP := "install_ownership_rule"
const ACTION_PARENT_TREE := "install_parent_child_rule"
const ACTION_TIME := "install_time_rule"
const ACTION_GO_TO_3D := "go_to_poc3"
const ACTION_RETURN_TO_2D := "return_to_poc2"

const DEMO_RULES := {
    ACTION_OBJECT_BASE: {
        "id": "rule_object_base",
        "name": "オブジェクト基礎ルール",
        "description": "物体エンティティを2D世界に出し、物として観察できるようにします。",
        "status": "道具袋・水瓶・倉庫・ベリー束が2D世界に現れます。",
        "parent_rule_ids": []
    },
    ACTION_OWNERSHIP: {
        "id": "rule_ownership_links",
        "name": "所有関係ルール",
        "description": "物体に所有者を結びつけ、誰の持ち物かを説明できるようにします。",
        "status": "道具袋と水瓶の所有者がプレイヤーとして表示されます。",
        "parent_rule_ids": ["rule_object_base"]
    },
    ACTION_PARENT_TREE: {
        "id": "rule_parent_child_tree",
        "name": "親子ツリールール",
        "description": "入れ物と中身、配置先を親子ツリーとして追えるようにします。",
        "status": "ベリー束 → 道具袋、水瓶 → 倉庫 の関係を確認できます。",
        "parent_rule_ids": ["rule_ownership_links"]
    }
}

const ENTITY_DEFINITIONS := {
    "player_character": {
        "name": "プレイヤー",
        "kind": "character",
        "color": Color(0.2, 0.6, 1.0, 1.0),
        "position_2d": Vector2(240.0, 360.0),
        "size_2d": Vector2(40.0, 40.0),
        "position_3d": Vector3(0.0, 0.9, -3.2),
        "size_3d": Vector3(0.9, 1.8, 0.9),
        "base_lines": ["役割: 2D世界を歩いてGMに相談する主人公です。"],
        "state_lines": ["目的: オブジェクト / 所有 / 親子ツリーの実演を確認する。"]
    },
    "game_master": {
        "name": "ゲームマスター",
        "kind": "character",
        "color": Color(1.0, 0.8, 0.2, 1.0),
        "position_2d": Vector2(1030.0, 370.0),
        "size_2d": Vector2(64.0, 64.0),
        "position_3d": Vector3(3.2, 1.1, 0.8),
        "size_3d": Vector3(1.2, 2.2, 1.2),
        "base_lines": ["役割: プレイヤーにルール段階を案内するGMです。"],
        "state_lines": ["案内: 物体基礎 → 所有関係 → 親子ツリー → 必要なら時間 / 3D。"]
    },
    "tool_satchel": {
        "name": "道具袋",
        "kind": "object",
        "color": Color(0.803922, 0.572549, 0.309804, 1.0),
        "position_2d": Vector2(720.0, 380.0),
        "size_2d": Vector2(84.0, 58.0),
        "position_3d": Vector3(0.8, 0.55, 0.2),
        "size_3d": Vector3(1.1, 1.0, 0.8),
        "base_lines": ["種別: object-base の携行物です。", "状態: 丈夫 / 肩掛け。"],
        "visible_after": ACTION_OBJECT_BASE
    },
    "berry_bundle": {
        "name": "ベリー束",
        "kind": "object",
        "color": Color(0.87451, 0.27451, 0.384314, 1.0),
        "position_2d": Vector2(840.0, 320.0),
        "size_2d": Vector2(56.0, 44.0),
        "position_3d": Vector3(1.65, 0.42, -0.35),
        "size_3d": Vector3(0.7, 0.5, 0.7),
        "base_lines": ["種別: object-base の食料。", "状態: 採れたて / 3食分。"],
        "visible_after": ACTION_OBJECT_BASE
    },
    "storehouse": {
        "name": "倉庫",
        "kind": "object",
        "color": Color(0.690196, 0.533333, 0.34902, 1.0),
        "position_2d": Vector2(930.0, 560.0),
        "size_2d": Vector2(138.0, 120.0),
        "position_3d": Vector3(3.0, 1.1, -1.3),
        "size_3d": Vector3(2.3, 2.2, 2.1),
        "base_lines": ["種別: object-base の保管場所。", "状態: 乾燥 / 在庫あり。"],
        "visible_after": ACTION_OBJECT_BASE
    },
    "water_jar": {
        "name": "水瓶",
        "kind": "object",
        "color": Color(0.490196, 0.768627, 0.905882, 1.0),
        "position_2d": Vector2(880.0, 520.0),
        "size_2d": Vector2(62.0, 74.0),
        "position_3d": Vector3(2.45, 0.7, -0.55),
        "size_3d": Vector3(0.9, 1.2, 0.9),
        "base_lines": ["種別: object-base の容器。", "状態: 半分まで充填 / 密閉済み。"],
        "visible_after": ACTION_OBJECT_BASE
    }
}

@onready var world_host: Node = $WorldHost
@onready var overlay_layer: CanvasLayer = $OverlayLayer

var _world_state: Node = null
var _active_world: Node = null
var _active_mode := "two_d"
var _gm_dialog: Control = null
var _progress := {
    "object_base": false,
    "ownership": false,
    "parent_tree": false
}
var _conversation_log: Array = []
var _selected_entity_id := DEFAULT_SELECTED_ENTITY_ID

func _ready() -> void:
    _world_state = get_node_or_null("/root/WorldState")
    _seed_conversation()
    _switch_world("two_d")

func get_poc_snapshot() -> Dictionary:
    var world_snapshot := _get_world_state_snapshot()
    var entities := _build_entities()
    var selected_entity := _find_entity(entities, _selected_entity_id)
    if selected_entity.is_empty():
        selected_entity = _find_entity(entities, "player_character")
    return {
        "active_mode": _active_mode,
        "progress": _progress.duplicate(true),
        "conversation": _conversation_log.duplicate(true),
        "installed_rules": _build_installed_rules(world_snapshot),
        "entities": entities,
        "selected_entity_id": String(selected_entity.get("id", "player_character")),
        "selected_entity": selected_entity,
        "goal_lines": _goal_lines(),
        "stage_title": _stage_title(),
        "stage_summary": _stage_summary(),
        "success_summary": _success_summary(),
        "time_rule_active": _time_rule_active(world_snapshot),
        "clock": _coerce_dictionary(world_snapshot.get("clock", {})),
        "world_name": "PoC3 3D途中証明" if _active_mode == "three_d" else "PoC2 2D実演世界",
        "poc3_note": "PoC3 の 3D化は途中証明です。成功導線は 2D の PoC2 です。"
    }

func submit_gm_message(message: String) -> Dictionary:
    var trimmed := message.strip_edges()
    if trimmed.is_empty():
        return {
            "status": "ignored",
            "gm_response": "",
            "close_after_action": false
        }

    _append_conversation("player", trimmed)
    var result := perform_gm_action(_classify_message(trimmed), trimmed)
    return result

func perform_gm_action(action_id: String, _message: String = "") -> Dictionary:
    var gm_response := ""
    var close_after_action := false

    match action_id:
        ACTION_OBJECT_BASE:
            if _progress.object_base:
                gm_response = "オブジェクト基礎ルールはすでに有効です。2D世界で物体をクリックして状態を確認してください。"
            else:
                _progress.object_base = true
                _selected_entity_id = "tool_satchel"
                gm_response = "オブジェクト基礎ルールを有効化しました。2D世界に道具袋・ベリー束・倉庫・水瓶が現れます。"
        ACTION_OWNERSHIP:
            if not _progress.object_base:
                gm_response = "先にオブジェクト基礎ルールを有効化してください。物体が現れてから所有関係を結びます。"
            elif _progress.ownership:
                gm_response = "所有関係ルールはすでに有効です。道具袋と水瓶の所有者がプレイヤーとして表示されています。"
            else:
                _progress.ownership = true
                _selected_entity_id = "water_jar"
                gm_response = "所有関係ルールを追加しました。道具袋と水瓶がプレイヤーの持ち物として見えるようになりました。"
        ACTION_PARENT_TREE:
            if not _progress.ownership:
                gm_response = "先に所有関係ルールまで進めてください。その後で親子ツリーをつなげます。"
            elif _progress.parent_tree:
                gm_response = "親子ツリールールはすでに有効です。ベリー束→道具袋、水瓶→倉庫 を確認できます。"
            else:
                _progress.parent_tree = true
                _selected_entity_id = "berry_bundle"
                gm_response = "親子ツリールールを追加しました。ベリー束は道具袋の子、水瓶は倉庫に配置された物体として追跡できます。PoC2 の本筋は達成です。"
        ACTION_TIME:
            gm_response = _install_time_rule()
        ACTION_GO_TO_3D:
            switch_world("three_d")
            gm_response = "PoC3 の 3D途中証明に切り替えました。2D の PoC2 が本筋なので、確認したら戻ってください。"
            close_after_action = true
        ACTION_RETURN_TO_2D:
            switch_world("two_d")
            gm_response = "2D の PoC2 実演世界へ戻します。こちらが成功導線です。"
            close_after_action = true
        _:
            gm_response = "本筋は「物体基礎」「所有関係」「親子ツリー」です。必要なら「時間」や「3D」も補助的に見せられます。"

    _append_conversation("gm", gm_response)
    _emit_snapshot_changed()
    return {
        "status": "ok",
        "gm_response": gm_response,
        "close_after_action": close_after_action
    }

func switch_world(mode: String) -> void:
    var normalized := "three_d" if mode == "three_d" else "two_d"
    if normalized == _active_mode and _active_world != null:
        return
    _switch_world(normalized)
    _emit_snapshot_changed()

func set_selected_entity(entity_id: String) -> void:
    var entities := _build_entities()
    for entity in entities:
        if String(entity.get("id", "")) == entity_id and bool(entity.get("visible", false)):
            _selected_entity_id = entity_id
            _emit_snapshot_changed()
            return

func _switch_world(mode: String) -> void:
    if _active_world != null:
        _active_world.queue_free()
        _active_world = null

    var packed_scene := WORLD_3D_SCENE if mode == "three_d" else WORLD_2D_SCENE
    _active_world = packed_scene.instantiate()
    world_host.add_child(_active_world)
    if _active_world.has_method("set_world_controller"):
        _active_world.call("set_world_controller", self)
    if _active_world.has_signal("gm_interaction_requested"):
        _active_world.gm_interaction_requested.connect(_on_gm_interaction_requested)
    _active_mode = mode
    if _gm_dialog == null and _active_world.has_method("set_interaction_paused"):
        _active_world.call("set_interaction_paused", false)

func _on_gm_interaction_requested() -> void:
    if _gm_dialog != null:
        return
    if _active_world != null and _active_world.has_method("set_interaction_paused"):
        _active_world.call("set_interaction_paused", true)

    _gm_dialog = GM_DIALOG_SCRIPT.new()
    overlay_layer.add_child(_gm_dialog)
    if _gm_dialog.has_method("set_world_controller"):
        _gm_dialog.call("set_world_controller", self)
    _gm_dialog.closed.connect(_on_gm_dialog_closed)

func _on_gm_dialog_closed() -> void:
    _gm_dialog = null
    if _active_world != null and _active_world.has_method("set_interaction_paused"):
        _active_world.call("set_interaction_paused", false)
    _emit_snapshot_changed()

func _seed_conversation() -> void:
    _conversation_log = [
        {
            "speaker": "gm",
            "text": "ようこそ。PoC2 の本筋は 2D 世界でオブジェクト基礎 → 所有関係 → 親子ツリーを順に確認することです。"
        },
        {
            "speaker": "gm",
            "text": "時間ルールや 3D 化は補助です。まずは物体ルールの実演を進めましょう。"
        }
    ]

func _append_conversation(speaker: String, text: String) -> void:
    _conversation_log.append({
        "speaker": speaker,
        "text": text
    })

func _goal_lines() -> Array:
    return [
        "1. 2D世界でGMに近づき、会話画面を開く。",
        "2. オブジェクト基礎 → 所有関係 → 親子ツリーを順に有効化する。",
        "3. 世界へ戻り、物体をクリックして所有 / 配置 / 親子状態を日本語で確認する。"
    ]

func _stage_title() -> String:
    if _progress.parent_tree:
        return "PoC2 達成: 2Dで物体・所有・親子ツリーを確認中"
    if _progress.ownership:
        return "所有関係まで導入済み"
    if _progress.object_base:
        return "物体基礎を導入済み"
    return "GMに話しかけて物体ルールを起動してください"

func _stage_summary() -> String:
    if _progress.parent_tree:
        return "ベリー束 → 道具袋、水瓶 → 倉庫 の関係が見えています。PoC3 は任意の途中証明です。"
    if _progress.ownership:
        return "道具袋と水瓶の所有者がプレイヤーに結びつきました。次は親子ツリーです。"
    if _progress.object_base:
        return "2D世界に物体が出現しました。次は所有関係をつないでください。"
    return "時間ルールだけでは終わりません。まず物体基礎を有効化して PoC2 を進めてください。"

func _success_summary() -> String:
    return "PoC2 の成功条件: 2D世界で Object Rule / Ownership Rule / parent-child rule tree / object ownership state を確認できること。"

func _build_installed_rules(world_snapshot: Dictionary) -> Array:
    var rules: Array = []
    if _progress.object_base:
        rules.append(_build_rule_entry(DEMO_RULES[ACTION_OBJECT_BASE]))
    if _progress.ownership:
        rules.append(_build_rule_entry(DEMO_RULES[ACTION_OWNERSHIP]))
    if _progress.parent_tree:
        rules.append(_build_rule_entry(DEMO_RULES[ACTION_PARENT_TREE]))
    if _time_rule_active(world_snapshot):
        rules.append({
            "id": "time_counter",
            "name": "時間ルール",
            "description": "右上の時計を進める補助ルールです。PoC2 の本筋ではなく補助確認用です。",
            "status": "時計が表示され、固定刻みで時刻が進行中です。",
            "parent_rule_ids": []
        })
    return rules

func _build_rule_entry(source: Dictionary) -> Dictionary:
    return {
        "id": String(source.get("id", "")),
        "name": String(source.get("name", "")),
        "description": String(source.get("description", "")),
        "status": String(source.get("status", "")),
        "parent_rule_ids": source.get("parent_rule_ids", []).duplicate(true)
    }

func _build_entities() -> Array:
    var entities: Array = []
    entities.append(_build_character_entity("player_character"))
    entities.append(_build_character_entity("game_master"))
    entities.append(_build_object_entity("tool_satchel"))
    entities.append(_build_object_entity("berry_bundle"))
    entities.append(_build_object_entity("storehouse"))
    entities.append(_build_object_entity("water_jar"))
    return entities

func _build_character_entity(entity_id: String) -> Dictionary:
    var source: Dictionary = ENTITY_DEFINITIONS[entity_id]
    var inspector_lines: Array = []
    inspector_lines.append_array(source.get("base_lines", []))
    inspector_lines.append_array(source.get("state_lines", []))
    if entity_id == "player_character" and _progress.ownership:
        inspector_lines.append("所有中: 道具袋 / 水瓶")
    return {
        "id": entity_id,
        "name": String(source.get("name", entity_id)),
        "kind": "character",
        "visible": true,
        "color": source.get("color", Color.WHITE),
        "position_2d": source.get("position_2d", Vector2.ZERO),
        "size_2d": source.get("size_2d", Vector2(40.0, 40.0)),
        "position_3d": source.get("position_3d", Vector3.ZERO),
        "size_3d": source.get("size_3d", Vector3.ONE),
        "owner_id": "",
        "container_id": "",
        "location_id": "",
        "child_ids": [],
        "owned_ids": ["tool_satchel", "water_jar"] if _progress.ownership and entity_id == "player_character" else [],
        "inspector_lines": inspector_lines,
        "summary": "プレイヤー" if entity_id == "player_character" else "GM"
    }

func _build_object_entity(entity_id: String) -> Dictionary:
    var source: Dictionary = ENTITY_DEFINITIONS[entity_id]
    var visible: bool = bool(_progress.get("object_base", false))
    var owner_id := ""
    var container_id := ""
    var location_id := ""
    var child_ids: Array = []
    var inspector_lines: Array = []
    inspector_lines.append_array(source.get("base_lines", []))

    if _progress.ownership and entity_id in ["tool_satchel", "water_jar"]:
        owner_id = "player_character"
        inspector_lines.append("所有者: プレイヤー")

    if _progress.parent_tree:
        if entity_id == "tool_satchel":
            child_ids.append("berry_bundle")
            inspector_lines.append("子: ベリー束")
        elif entity_id == "berry_bundle":
            container_id = "tool_satchel"
            inspector_lines.append("親 / 入れ物: 道具袋")
        elif entity_id == "water_jar":
            location_id = "storehouse"
            inspector_lines.append("配置先: 倉庫")
        elif entity_id == "storehouse":
            child_ids.append("water_jar")
            inspector_lines.append("配置中: 水瓶")

    return {
        "id": entity_id,
        "name": String(source.get("name", entity_id)),
        "kind": "object",
        "visible": visible,
        "color": source.get("color", Color.WHITE),
        "position_2d": source.get("position_2d", Vector2.ZERO),
        "size_2d": source.get("size_2d", Vector2(60.0, 60.0)),
        "position_3d": source.get("position_3d", Vector3.ZERO),
        "size_3d": source.get("size_3d", Vector3.ONE),
        "owner_id": owner_id,
        "container_id": container_id,
        "location_id": location_id,
        "child_ids": child_ids,
        "owned_ids": [],
        "inspector_lines": inspector_lines,
        "summary": _entity_summary(owner_id, container_id, location_id, child_ids)
    }

func _entity_summary(owner_id: String, container_id: String, location_id: String, child_ids: Array) -> String:
    var parts: Array = []
    if owner_id != "":
        parts.append("所有者: プレイヤー")
    if container_id != "":
        parts.append("入れ物: 道具袋")
    if location_id != "":
        parts.append("配置先: 倉庫")
    if not child_ids.is_empty():
        if child_ids.has("berry_bundle"):
            parts.append("子: ベリー束")
        if child_ids.has("water_jar"):
            parts.append("配置: 水瓶")
    return " / ".join(parts) if not parts.is_empty() else "物体として確認可能"

func _install_time_rule() -> String:
    if _world_state != null and _world_state.has_method("talk_to_game_master"):
        var result_variant = _world_state.call("talk_to_game_master", "時間のルールを作成しろ")
        if result_variant is Dictionary:
            var result: Dictionary = result_variant
            return String(result.get("gm_response", result.get("reply", "時計ルールを更新しました。")))
    return "WorldState が見つからないため、時間ルールは補助表示のみです。"

func _classify_message(message: String) -> String:
    var normalized := message.strip_edges().to_lower()
    if normalized.findn("親子") != -1 or normalized.findn("ツリー") != -1 or normalized.findn("入れ物") != -1:
        return ACTION_PARENT_TREE
    if normalized.findn("所有") != -1 or normalized.findn("owner") != -1:
        return ACTION_OWNERSHIP
    if normalized.findn("物体") != -1 or normalized.findn("object") != -1 or normalized.findn("オブジェクト") != -1:
        return ACTION_OBJECT_BASE
    if normalized.findn("時間") != -1 or normalized.findn("時計") != -1 or normalized.findn("time") != -1:
        return ACTION_TIME
    if normalized.findn("3d") != -1 or normalized.findn("3d化") != -1:
        return ACTION_GO_TO_3D
    if normalized.findn("2d") != -1 or normalized.findn("戻") != -1:
        return ACTION_RETURN_TO_2D
    return "help"

func _time_rule_active(world_snapshot: Dictionary) -> bool:
    var clock := _coerce_dictionary(world_snapshot.get("clock", {}))
    if bool(clock.get("visible", false)):
        return true

    var installed_rules_variant: Variant = world_snapshot.get("installed_rules_by_id", world_snapshot.get("installed_rules", {}))
    if installed_rules_variant is Dictionary:
        var installed_rules: Dictionary = installed_rules_variant
        return installed_rules.has("time_counter") or installed_rules.has("rule_world_time")
    if installed_rules_variant is Array:
        var installed_rule_array: Array = installed_rules_variant
        for entry in installed_rule_array:
            if entry is Dictionary:
                var rule_id := String(entry.get("id", ""))
                if rule_id == "time_counter" or rule_id == "rule_world_time":
                    return true
    return false

func _get_world_state_snapshot() -> Dictionary:
    if _world_state != null and _world_state.has_method("get_world_snapshot"):
        var snapshot_variant = _world_state.call("get_world_snapshot")
        if snapshot_variant is Dictionary:
            return snapshot_variant
    return {}

func _find_entity(entities: Array, entity_id: String) -> Dictionary:
    for entity in entities:
        if String(entity.get("id", "")) == entity_id and bool(entity.get("visible", false)):
            return entity
    return {}

func _coerce_dictionary(value: Variant) -> Dictionary:
    return value if value is Dictionary else {}

func _emit_snapshot_changed() -> void:
    poc_snapshot_changed.emit()
