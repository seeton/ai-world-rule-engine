const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const repoRoot = path.resolve(__dirname, "..");
const runtimePath = path.join(repoRoot, "godot-world", "scripts", "core", "SimulationRuntime.gd");
const uiPath = path.join(repoRoot, "godot-world", "scripts", "ui", "main_desktop.gd");
const compilerPath = path.join(repoRoot, "godot-world", "scripts", "integration", "runtime_rule_patch_compiler.gd");

test("world clock summary derives provider metadata from the matched rule", () => {
  const runtimeSource = fs.readFileSync(runtimePath, "utf8");

  assert.match(runtimeSource, /var provider := _find_world_clock_provider\(installed_rules_by_id\)/);
  assert.match(runtimeSource, /"source_package_id": String\(provider.get\("source_package_id", ""\)\)/);
  assert.match(runtimeSource, /"source_rule_id": String\(provider.get\("source_rule_id", ""\)\)/);
  assert.match(runtimeSource, /func _find_world_clock_provider\(installed_rules_by_id: Dictionary\) -> Dictionary:/);
});

test("world clock UI uses snapshot source metadata instead of hardcoding builtin.time", () => {
  const uiSource = fs.readFileSync(uiPath, "utf8");

  assert.match(uiSource, /var source_label := str\(world_clock.get\("source_package_id", world_clock.get\("source_rule_id", ""\)\)\)/);
  assert.doesNotMatch(uiSource, /builtin\.time → WorldState/);
});

test("runtime rule compiler keys stat definitions with the compiled stat field", () => {
  const compilerSource = fs.readFileSync(compilerPath, "utf8");

  assert.match(compilerSource, /var stat_id := String\(compiled_effect.get\("field", "value"\)\)/);
});
