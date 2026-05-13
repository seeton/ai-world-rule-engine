const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const repoRoot = path.resolve(__dirname, "..");
const worldStatePath = path.join(repoRoot, "godot-world", "scripts", "core", "WorldState.gd");
const uiPath = path.join(repoRoot, "godot-world", "scripts", "ui", "main_desktop.gd");
const readmePath = path.join(repoRoot, "godot-world", "README.md");
const ruleCompilerPath = path.join(repoRoot, "godot-world", "scripts", "integration", "rule_compiler.gd");
const compilerPath = path.join(repoRoot, "godot-world", "scripts", "integration", "runtime_rule_patch_compiler.gd");

test("WorldState routes package installs through review before runtime install", () => {
  const source = fs.readFileSync(worldStatePath, "utf8");

  assert.match(source, /func review_rule_package_proposal\(rule_package: Dictionary\) -> Dictionary:/);
  assert.match(source, /if String\(review_result.get\("status", ""\)\) != "ready_for_install":/);
  assert.match(source, /"install_source": "rule_package"/);
  assert.match(source, /"compiled_runtime_patch": compilation.get\("runtime_patch", \{\}\)\.duplicate\(true\)/);
  assert.match(source, /var dependency_resolution := _resolve_rule_package_dependencies\(rule_package\)/);
  assert.match(source, /var compiled_runtime_rules := _extract_compiled_runtime_rules\(compilation\)/);
  assert.match(source, /for runtime_target_variant in runtime_targets:/);
});

test("runtime exposes collapsed dependency state without making defaults engine invariants", () => {
  const source = fs.readFileSync(path.join(repoRoot, "godot-world", "scripts", "core", "SimulationRuntime.gd"), "utf8");

  assert.match(source, /snapshot\["rule_dependency_status"\] = _build_rule_dependency_status\(installed_rules_by_id\)/);
  assert.match(source, /"blocked_rule_ids": blocked_rule_ids/);
  assert.match(source, /"inactive_rule_ids": inactive_rule_ids/);
  assert.match(source, /"missing_required_rule_kinds_by_rule_id": missing_required_rule_kinds_by_rule_id/);
  assert.match(source, /rule\["blocked"\] = not missing_required_rule_kinds\.is_empty\(\)/);
});

test("GM UI exposes proposal review metadata and approval gating", () => {
  const source = fs.readFileSync(uiPath, "utf8");

  assert.match(source, /func _build_proposal_panel\(\) -> Control:/);
  assert.match(source, /clone \/ fork 元:/);
  assert.match(source, /提案PR先:/);
  assert.match(source, /宣言的な導入アクション/);
  assert.match(source, /ルールパッケージ patch は辞書型である必要があります。/);
  assert.match(source, /if String\(_current_proposal_review.get\("review_status", ""\)\) != "approved":/);
  assert.match(source, /_proposal_requires_reapproval/);
});

test("runtime compiler preserves declarative install actions for traceable installs", () => {
  const source = fs.readFileSync(compilerPath, "utf8");

  assert.match(source, /var patch_install_actions_result := _validate_install_actions\(patch.get\("install_actions", \[\]\)\)/);
  assert.match(source, /"install_actions": patch_install_actions\.duplicate\(true\)/);
  assert.match(source, /"runtime_rules": _duplicate_dictionary_array\(runtime_rules\)/);
  assert.match(source, /func _validate_install_actions\(raw_actions: Variant\) -> Dictionary:/);
  assert.match(source, /func _validate_operations\(raw_operations: Variant\) -> Dictionary:/);
  assert.match(source, /Rule package patch\.operations\[%d\] must be a dictionary\./);
});

test("WorldState validates package operations and README documents package installs", () => {
  const source = fs.readFileSync(worldStatePath, "utf8");
  const readme = fs.readFileSync(readmePath, "utf8");

  assert.match(source, /func _validate_rule_package_operations\(operations_variant: Variant, rule_package: Dictionary\) -> Dictionary:/);
  assert.match(source, /Rule package patch\.operations\[%d\] must include a non-empty op\./);
  assert.match(source, /if refreshed_rule_packages or _available_rule_packages.is_empty\(\):/);
  assert.match(readme, /accepts either a runtime rule patch or a reviewed rule package proposal/i);
});

test("RuleCompiler keeps a typed shared repository helper", () => {
  const source = fs.readFileSync(ruleCompilerPath, "utf8");

  assert.match(source, /const RulePackageRepositoryScript = preload\("res:\/\/scripts\/integration\/rule_package_repository\.gd"\)/);
  assert.match(source, /var _repository = null/);
  assert.doesNotMatch(source, /load\("res:\/\/scripts\/integration\/rule_package_repository\.gd"\)\.new\(\)/);
});
