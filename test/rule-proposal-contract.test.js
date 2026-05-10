const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const repoRoot = path.resolve(__dirname, "..");
const schemaPath = path.join(repoRoot, "godot-world", "rules", "schema", "rule_proposal.schema.json");
const worldStatePath = path.join(repoRoot, "godot-world", "scripts", "core", "WorldState.gd");
const runtimePath = path.join(repoRoot, "godot-world", "scripts", "core", "SimulationRuntime.gd");
const gmDialogPath = path.join(repoRoot, "godot-world", "scripts", "ui", "gm_dialog.gd");
const mainDesktopPath = path.join(repoRoot, "godot-world", "scripts", "ui", "main_desktop.gd");
const gmScreenOverlayPath = path.join(repoRoot, "godot-world", "scripts", "game", "gm_screen_overlay.gd");

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function collectEnumLikeNodes(schema, findings = [], trail = []) {
  if (!schema || typeof schema !== "object") {
    return findings;
  }

  if ((Object.hasOwn(schema, "const") || Object.hasOwn(schema, "enum")) && !Object.hasOwn(schema, "type")) {
    findings.push(trail.join(".") || "<root>");
  }

  if (schema.properties && typeof schema.properties === "object") {
    for (const [key, value] of Object.entries(schema.properties)) {
      collectEnumLikeNodes(value, findings, [...trail, "properties", key]);
    }
  }

  if (schema.items) {
    collectEnumLikeNodes(schema.items, findings, [...trail, "items"]);
  }

  return findings;
}

test("rule proposal schema keeps enum/const nodes codex-compatible", () => {
  const schema = readJson(schemaPath);
  const findings = collectEnumLikeNodes(schema);

  assert.deepEqual(findings, [], `Schema enum/const nodes must declare an explicit type: ${findings.join(", ")}`);
  assert.equal(schema.required.includes("issue"), true);
  assert.equal(schema.required.includes("patch"), true);
});

test("PoC4 backend API is exposed from WorldState and SimulationRuntime", () => {
  const worldStateSource = fs.readFileSync(worldStatePath, "utf8");
  const runtimeSource = fs.readFileSync(runtimePath, "utf8");

  for (const signature of [
     "func talk_to_game_master(message: String) -> Dictionary:",
     "func talk_to_game_master_async(message: String) -> Dictionary:",
     "func request_rule_proposal(task_text: String) -> Dictionary:",
     "func request_rule_proposal_async(task_text: String) -> Dictionary:",
     "func get_pending_rule_proposal() -> Dictionary:",
     "func update_pending_rule_review(reviewed: bool, metadata: Dictionary = {}) -> Dictionary:",
     "func apply_pending_rule_proposal() -> Dictionary:",
     "func get_last_rule_apply_result() -> Dictionary:",
   ]) {
    assert.equal(worldStateSource.includes(signature), true, `Missing WorldState API: ${signature}`);
  }

  for (const signature of [
      'func begin_poc4_proposal_execution(request_text: String, codex_details: Dictionary = {}) -> Dictionary:',
      'func record_poc4_proposal(request_text: String, proposal_result: Dictionary) -> void:',
      'func update_poc4_review(reviewed: bool, metadata: Dictionary = {}) -> Dictionary:',
      'func apply_pending_poc4_proposal() -> Dictionary:',
      'func get_pending_poc4_proposal_state() -> Dictionary:',
      'func record_poc4_apply_result(apply_result: Dictionary) -> void:',
      'func get_last_poc4_apply_result() -> Dictionary:',
      '"review": review,',
      '"apply_result": _duplicate_dictionary(poc4_state.get("apply_result", {}))',
      '"execution": _duplicate_dictionary(poc4_state.get("execution", {}))',
      'snapshot["poc4"] = _get_poc4_state()',
   ]) {
    assert.equal(runtimeSource.includes(signature), true, `Missing runtime PoC4 state hook: ${signature}`);
  }
});

test("PoC4 codex details propagate into runtime and review UIs", () => {
  const runtimeSource = fs.readFileSync(runtimePath, "utf8");
  const gmDialogSource = fs.readFileSync(gmDialogPath, "utf8");
  const mainDesktopSource = fs.readFileSync(mainDesktopPath, "utf8");

  for (const snippet of [
    'poc4_state["codex"] = _merge_dictionaries(',
    '"codex": _duplicate_dictionary(poc4_state.get("codex", {}))',
    '"execution": _build_default_poc4_execution()',
    '"review": _build_default_poc4_review()',
    '"apply_result": {}',
    '"codex": {},',
  ]) {
    assert.equal(runtimeSource.includes(snippet), true, `Missing runtime codex state hook: ${snippet}`);
  }

  for (const snippet of [
    '"execution": _duplicate_dict(state.get("execution", {}))',
    '[b]PoC4 execution[/b]: %s',
    '"codex": _duplicate_dict(state.get("codex", {}))',
    '"review": _duplicate_dict(state.get("review", {}))',
    '"apply_result": _duplicate_dict(state.get("apply_result", {}))',
    '[b]apply_result[/b]: %s',
    '[b]runtime_rule_id[/b]: %s',
    '[b]session id[/b]: %s',
    '[b]model[/b]: %s',
    '[b]workdir[/b]: %s',
    '[b]approval[/b]: %s',
    '[b]sandbox[/b]: %s',
  ]) {
    assert.equal(gmDialogSource.includes(snippet), true, `Missing gm_dialog codex detail output: ${snippet}`);
  }

  for (const snippet of [
    '"execution": state.get("execution", {}).duplicate(true)',
    'lines.append("Execution:")',
    '"codex": state.get("codex", {}).duplicate(true)',
    'lines.append("Review:")',
    'lines.append("Apply result:")',
    'return "runtime install"',
    '- session id: %s',
    '- model: %s',
    '- workdir: %s',
    '- approval: %s',
    '- sandbox: %s',
  ]) {
    assert.equal(mainDesktopSource.includes(snippet), true, `Missing main_desktop codex detail output: ${snippet}`);
  }
});

test("PoC4 playable flow is apply-only instead of issue creation", () => {
  const worldStateSource = fs.readFileSync(worldStatePath, "utf8");
  const runtimeSource = fs.readFileSync(runtimePath, "utf8");
  const gmDialogSource = fs.readFileSync(gmDialogPath, "utf8");
  const mainDesktopSource = fs.readFileSync(mainDesktopPath, "utf8");

  for (const snippet of [
    'return _runtime.apply_pending_poc4_proposal()',
    'return _runtime.get_last_poc4_apply_result()',
    '"status": "ready_to_apply" if reviewed else "awaiting_review"',
    '"status": "applied_with_warnings" if not deferred_operations.is_empty() else "applied"',
    '"runtime_rule_id": runtime_rule.get("id", runtime_patch.get("id", ""))',
  ]) {
    assert.equal(runtimeSource.includes(snippet) || worldStateSource.includes(snippet), true, `Missing apply-only backend flow: ${snippet}`);
  }

  for (const snippet of [
    'proposal を確認し、必要ならそのままゲームへ適用できます。',
    '"apply_pending_rule_proposal"',
    '[b]apply_result[/b]: %s',
    'proposal をゲームへ適用しました。',
  ]) {
    assert.equal(gmDialogSource.includes(snippet), true, `Missing apply-only gm_dialog flow: ${snippet}`);
  }

  for (const snippet of [
    'PoC4 proposal / apply 状態',
    'apply 結果、backend error を read-only で確認します。',
    'var apply_result: Dictionary = merged_state.get("apply_result", {}).duplicate(true)',
    'return "runtime install"',
  ]) {
    assert.equal(mainDesktopSource.includes(snippet), true, `Missing apply-only main_desktop flow: ${snippet}`);
  }
});

test("PoC4 runtime supports input-driven visual effects for applied rules", () => {
  const worldStateSource = fs.readFileSync(worldStatePath, "utf8");
  const runtimeSource = fs.readFileSync(runtimePath, "utf8");
  const compilerPath = path.join(repoRoot, "godot-world", "scripts", "integration", "runtime_rule_patch_compiler.gd");
  const compilerSource = fs.readFileSync(compilerPath, "utf8");
  const world2dPath = path.join(repoRoot, "godot-world", "scripts", "game", "world_2d_scene.gd");
  const world3dPath = path.join(repoRoot, "godot-world", "scripts", "game", "world_3d_scene.gd");
  const burstPath = path.join(repoRoot, "godot-world", "scripts", "game", "visual_effect_burst_2d.gd");
  const world2dSource = fs.readFileSync(world2dPath, "utf8");
  const world3dSource = fs.readFileSync(world3dPath, "utf8");
  const burstSource = fs.readFileSync(burstPath, "utf8");

  for (const snippet of [
    'func dispatch_input_event(event_name: String, context: Dictionary = {}) -> Dictionary:',
    'return _runtime.dispatch_input_event(event_name, context)',
  ]) {
    assert.equal(worldStateSource.includes(snippet), true, `Missing WorldState input dispatch hook: ${snippet}`);
  }

  for (const snippet of [
    '"proposal_runtime": {}',
    '"visual_effects": []',
    'snapshot["visual_effects"] = _build_visual_effects_snapshot(Array(_world_state.get("visual_effects", [])))',
    'func dispatch_input_event(event_name: String, context: Dictionary = {}) -> Dictionary:',
    '"event_visual_effect"',
    '"spawn_visual_effect"',
    '_spawn_visual_effect(',
  ]) {
    assert.equal(runtimeSource.includes(snippet), true, `Missing SimulationRuntime visual effect support: ${snippet}`);
  }

  for (const snippet of [
    'elif rule_type in ["event_visual_effect"]',
    '"add_event_binding", "add_relation":',
  ]) {
    assert.equal(compilerSource.includes(snippet), true, `Missing compiler support for visual effect rule ops: ${snippet}`);
  }

  for (const snippet of [
    'const VisualEffectBurstScript := preload("res://scripts/game/visual_effect_burst_2d.gd")',
    '"dispatch_input_event"',
    '"input.key.%s.pressed" % key_name',
    '_sync_visual_effects(snapshot.get("visual_effects", []))',
  ]) {
    assert.equal(world2dSource.includes(snippet), true, `Missing 2D visual effect wiring: ${snippet}`);
    assert.equal(world3dSource.includes(snippet), true, `Missing 3D visual effect wiring: ${snippet}`);
  }

  for (const snippet of [
    'func apply_effect(effect: Dictionary, screen_position: Vector2) -> void:',
    'draw_line(',
    'draw_circle(',
  ]) {
    assert.equal(burstSource.includes(snippet), true, `Missing burst visual script behavior: ${snippet}`);
  }
});

test("playable GM overlay reaches both PoC4 conversation and admin UI", () => {
  const overlaySource = fs.readFileSync(gmScreenOverlayPath, "utf8");

  for (const snippet of [
    'const GM_DIALOG_SCRIPT := preload("res://scripts/ui/gm_dialog.gd")',
    'const MAIN_DESKTOP_SCRIPT := preload("res://scripts/ui/main_desktop.gd")',
    '_conversation_view = GM_DIALOG_SCRIPT.new()',
    '_admin_view = MAIN_DESKTOP_SCRIPT.new()',
    '_set_mode("conversation")',
    '_conversation_button.text = "プレイヤー会話 / PoC4 review"',
    '_admin_button.text = "管理 / デバッグ"',
  ]) {
    assert.equal(overlaySource.includes(snippet), true, `Missing playable overlay wiring: ${snippet}`);
  }
});
