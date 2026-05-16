const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const repoRoot = path.resolve(__dirname, "..");
const overlayPath = path.join(repoRoot, "godot-world", "scripts", "game", "cli_inspect_overlay.gd");
const readmePath = path.join(repoRoot, "godot-world", "README.md");

test("World CLI overlay exposes tab completion and keyboard-first input flow", () => {
  const source = fs.readFileSync(overlayPath, "utf8");
  const readme = fs.readFileSync(readmePath, "utf8");

  assert.match(source, /const CLI_COMPLETION_TEMPLATES := \[/);
  assert.match(source, /"value": "package install ", "summary": "指定 package を現在の world に導入"/);
  assert.match(source, /_input\.text_changed\.connect\(_on_input_text_changed\)/);
  assert.match(source, /_completion_list = ItemList\.new\(\)/);
  assert.match(source, /KEY_TAB:/);
  assert.match(source, /_handle_tab_completion\(\)/);
  assert.match(source, /_input\.keep_editing_on_text_submit = true/);
  assert.match(source, /func _request_input_focus\(\) -> void:/);
  assert.match(source, /call_deferred\("_finalize_input_focus"\)/);
  assert.match(source, /func _finalize_input_focus\(\) -> void:/);
  assert.match(source, /_input\.caret_column = _input\.text\.length\(\)/);
  assert.match(source, /func _build_rule_completion_candidates\(action: String, partial_rule_id: String\) -> Array:/);
  assert.match(source, /func _build_package_completion_candidates\(partial_package_id: String\) -> Array:/);
  assert.match(source, /summary = "%s: %s" % \[display_name, description\]/);
  assert.match(source, /trimmed_query == "package install"/);
  assert.match(source, /入力に一致する package が見つかりません/);
  assert.match(source, /trimmed_query == "rule %s" % String\(tokens\[1\]\)/);
  assert.match(source, /func _completion_value_matches_query\(value: String, query_lower: String, query_tokens: PackedStringArray\) -> bool:/);
  assert.match(source, /if query_tokens\.size\(\) == 1:/);
  assert.match(source, /String\(value_token\)\.begins_with\(token\)/);
  assert.match(source, /現在の world には導入済み rule がないため、%s 候補はありません/);
  assert.match(source, /現在は無効な rule がないため、enable 候補はありません/);
  assert.match(source, /現在は有効な rule がないため、disable 候補はありません/);
  assert.match(source, /if enabled != target_enabled_state:/);
  assert.match(source, /入力に一致する rule が見つかりません/);
  assert.match(source, /func _navigate_history\(direction: int\) -> void:/);
  assert.match(source, /_history_draft = _input\.text/);
  assert.match(readme, /press `C` in either the 2D or 3D world to open the dispatcher-backed `World CLI` overlay \(`inspect`, `rule`, `package`, `snapshot`, `help`, `clear`\)/i);
  assert.match(readme, /inside the `World CLI` overlay, `Enter` keeps focus on the command line, `↑↓` navigates history, and `Tab` shows\/applies command completions including `package install <package_id>` suggestions/i);
});
