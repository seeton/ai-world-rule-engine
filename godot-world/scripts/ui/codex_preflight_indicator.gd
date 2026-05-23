extends PanelContainer
class_name CodexPreflightIndicator

const POLL_SECONDS := 3.0

const _STATE_COLORS := {
	"ready": Color("#7ec488"),
	"running": Color("#74b3d4"),
	"degraded": Color("#e8a464"),
	"offline": Color("#e07474"),
}

var _world_state: Node = null
var _status_label: Label
var _checks_label: Label
var _recent_label: Label
var _refresh_timer: Timer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -320.0
	offset_top = -102.0
	offset_right = -20.0
	offset_bottom = -18.0
	custom_minimum_size = Vector2(300.0, 84.0)
	_world_state = get_node_or_null("/root/WorldState")
	_build_ui()
	_refresh_status(true)

	_refresh_timer = Timer.new()
	_refresh_timer.one_shot = false
	_refresh_timer.wait_time = POLL_SECONDS
	_refresh_timer.timeout.connect(_on_refresh_timer_timeout)
	add_child(_refresh_timer)
	_refresh_timer.start()


func _build_ui() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.08, 0.11, 0.92)
	panel_style.border_color = Color(1.0, 1.0, 1.0, 0.14)
	panel_style.set_border_width_all(1)
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.content_margin_left = 12
	panel_style.content_margin_top = 10
	panel_style.content_margin_right = 12
	panel_style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", panel_style)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 4)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color("#f3f5f8"))
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_status_label)

	_checks_label = Label.new()
	_checks_label.name = "ChecksLabel"
	_checks_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_checks_label.add_theme_font_size_override("font_size", 11)
	_checks_label.add_theme_color_override("font_color", Color("#c8ccd4"))
	_checks_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_checks_label)

	_recent_label = Label.new()
	_recent_label.name = "RecentLabel"
	_recent_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_recent_label.add_theme_font_size_override("font_size", 11)
	_recent_label.add_theme_color_override("font_color", Color("#a8acb7"))
	_recent_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_recent_label)


func _on_refresh_timer_timeout() -> void:
	_refresh_status(false)


func _refresh_status(force_refresh: bool) -> void:
	var snapshot: Dictionary = _fetch_status_snapshot(force_refresh)
	var overall_status := String(snapshot.get("overall_status", "offline"))
	var accent: Color = _STATE_COLORS.get(overall_status, Color("#a8acb7"))
	_status_label.text = "Codex %s" % _status_text(overall_status)
	_status_label.add_theme_color_override("font_color", accent)

	var cli_text := "CLI OK" if bool(snapshot.get("cli_available", false)) else "CLI NG"
	var login_text := "Login OK" if bool(snapshot.get("login_ok", false)) else "Login NG"
	var schema_text := "Schema OK" if bool(snapshot.get("schema_ready", false)) else "Schema NG"
	_checks_label.text = "%s / %s / %s" % [cli_text, login_text, schema_text]

	var recent: Dictionary = snapshot.get("recent", {})
	_recent_label.text = _recent_text(snapshot, recent)


func _fetch_status_snapshot(force_refresh: bool) -> Dictionary:
	if _world_state == null:
		_world_state = get_node_or_null("/root/WorldState")
	if _world_state == null or not _world_state.has_method("get_codex_preflight_status"):
		return {
			"overall_status": "offline",
			"cli_available": false,
			"login_ok": false,
			"schema_ready": false,
			"recent": {
				"status": "idle",
				"message": "WorldState unavailable",
			},
		}
	var status_variant = _world_state.call("get_codex_preflight_status", force_refresh)
	return status_variant if status_variant is Dictionary else {}


func _status_text(status: String) -> String:
	match status:
		"ready":
			return "Ready"
		"running":
			return "Running"
		"degraded":
			return "Degraded"
		_:
			return "Offline"


func _recent_text(snapshot: Dictionary, recent: Dictionary) -> String:
	var recent_status := String(recent.get("status", "idle"))
	match recent_status:
		"running":
			return "直近: proposal 生成中"
		"proposal_ready":
			var package_id := String(recent.get("package_id", "")).strip_edges()
			return "直近: proposal 成功%s" % (" (%s)" % package_id if not package_id.is_empty() else "")
		"error":
			var error_code := String(recent.get("error_code", "")).strip_edges()
			return "直近: %s" % (error_code if not error_code.is_empty() else String(recent.get("message", "error")))
		_:
			if not bool(snapshot.get("login_ok", false)):
				return String(snapshot.get("login_message", "未ログイン"))
			if not bool(snapshot.get("schema_ready", false)):
				return String(snapshot.get("schema_message", "schema 未準備"))
			return "直近: まだ実行なし"
