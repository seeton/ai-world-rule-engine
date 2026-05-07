const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const repoRoot = path.resolve(__dirname, "..");
const worldStatePath = path.join(repoRoot, "godot-world", "scripts", "core", "WorldState.gd");
const uiPath = path.join(repoRoot, "godot-world", "scripts", "ui", "main_desktop.gd");
const compilerPath = path.join(repoRoot, "godot-world", "scripts", "integration", "runtime_rule_patch_compiler.gd");

test("WorldState routes package installs through review before runtime install", () => {
  const source = fs.readFileSync(worldStatePath, "utf8");

  assert.match(source, /func review_rule_package_proposal\(rule_package: Dictionary\) -> Dictionary:/);
  assert.match(source, /if String\(review_result.get\("status", ""\)\) != "ready_for_install":/);
  assert.match(source, /install_result\["install_source"\] = "rule_package"/);
  assert.match(source, /install_result\["compiled_runtime_patch"\] = compilation.get\("runtime_patch", \{\}\)\.duplicate\(true\)/);
});

test("GM UI exposes proposal review metadata and approval gating", () => {
  const source = fs.readFileSync(uiPath, "utf8");

  assert.match(source, /func _build_proposal_panel\(\) -> Control:/);
  assert.match(source, /clone \/ fork 元:/);
  assert.match(source, /提案PR先:/);
  assert.match(source, /宣言的な導入アクション/);
  assert.match(source, /if String\(_current_proposal_review.get\("review_status", ""\)\) != "approved":/);
  assert.match(source, /_proposal_requires_reapproval/);
});

test("runtime compiler preserves declarative install actions for traceable installs", () => {
  const source = fs.readFileSync(compilerPath, "utf8");

  assert.match(source, /"install_actions": _duplicate_install_actions\(patch.get\("install_actions", \[\]\)\)/);
  assert.match(source, /func _duplicate_install_actions\(raw_actions: Variant\) -> Array:/);
});
