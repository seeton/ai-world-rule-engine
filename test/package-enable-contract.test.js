const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const repoRoot = path.resolve(__dirname, "..");
const runtimePath = path.join(repoRoot, "godot-world", "scripts", "core", "SimulationRuntime.gd");
const worldStatePath = path.join(repoRoot, "godot-world", "scripts", "core", "WorldState.gd");
const uiPath = path.join(repoRoot, "godot-world", "scripts", "ui", "main_desktop.gd");
const cliParserPath = path.join(repoRoot, "godot-world", "scripts", "cli", "cli_command_parser.gd");
const readmePath = path.join(repoRoot, "godot-world", "README.md");

test("runtime exposes installed package summaries and a package toggle API", () => {
  const source = fs.readFileSync(runtimePath, "utf8");

  assert.match(source, /snapshot\["installed_rule_packages_by_id"\] = installed_package_summary\.get\("packages_by_id", \{\}\)\.duplicate\(true\)/);
  assert.match(source, /snapshot\["installed_rule_packages"\] = installed_package_summary\.get\("packages", \[\]\)\.duplicate\(true\)/);
  assert.match(source, /func set_package_enabled\(package_id: String, enabled: bool\) -> Dictionary:/);
  assert.match(source, /func set_rule_enabled\(rule_id: String, enabled: bool\) -> Dictionary:[\s\S]*?_refresh_rule_relationships\(\)/);
  assert.match(source, /func set_package_enabled\(package_id: String, enabled: bool\) -> Dictionary:[\s\S]*?_refresh_rule_relationships\(\)/);
  assert.match(source, /func set_package_enabled\(package_id: String, enabled: bool\) -> Dictionary:[\s\S]*?_set_proposal_runtime_package_enabled\(normalized_package_id, enabled\)/);
  assert.match(source, /if not bool\(package_runtime.get\("enabled", true\)\):[\s\S]*?continue/);
  assert.match(source, /func _build_installed_rule_packages\(installed_rules_by_id: Dictionary\) -> Dictionary:/);
});

test("WorldState and CLI surface package enable/disable as first-class operations", () => {
  const worldState = fs.readFileSync(worldStatePath, "utf8");
  const cliParser = fs.readFileSync(cliParserPath, "utf8");

  assert.match(worldState, /func get_installed_rule_packages\(\) -> Array:/);
  assert.match(worldState, /func set_package_enabled\(package_id: String, enabled: bool\) -> Dictionary:/);
  assert.match(cliParser, /"operation_type": "EnablePackage"/);
  assert.match(cliParser, /"operation_type": "DisablePackage"/);
  assert.match(cliParser, /package enable <package_id>/);
  assert.match(cliParser, /package disable <package_id>/);
});

test("GM UI exposes package controls and README documents package APIs", () => {
  const uiSource = fs.readFileSync(uiPath, "utf8");
  const readme = fs.readFileSync(readmePath, "utf8");

  assert.match(uiSource, /_package_enable_button\.text = "選択パッケージを有効化"/);
  assert.match(uiSource, /_package_disable_button\.text = "選択パッケージを無効化"/);
  assert.match(uiSource, /WorldOpDispatcherScript\.dispatch\(_world_state, operation_type, \{"package_id": package_id\}, \{\}\)/);
  assert.match(readme, /get_installed_rule_packages\(\) -> Array/);
  assert.match(readme, /set_package_enabled\(package_id: String, enabled: bool\) -> Dictionary/);
});
