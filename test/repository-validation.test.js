const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const { after, test } = require("node:test");

const repoRoot = path.resolve(__dirname, "..");
const validatorPath = path.join(repoRoot, "godot-world", "scripts", "validate_repo.py");
const wrapperPath = path.join(repoRoot, "godot-world", "scripts", "validate_repo.sh");
const schemaPath = path.join(repoRoot, "godot-world", "rules", "schema", "rule_package.schema.json");
const packagePath = path.join(repoRoot, "godot-world", "rules", "packages", "time.rule.json");
const defaultPackagePath = path.join(repoRoot, "godot-world", "rules", "packages", "default_package.rule.json");
const peacefulWorldOrderPath = path.join(repoRoot, "godot-world", "rules", "packages", "peaceful_world_order.rule.json");
const scratchRoot = path.join(repoRoot, "test", ".scratch", "repository-validation");

function runValidator(args) {
  return spawnSync("python3", [validatorPath, ...args], {
    cwd: repoRoot,
    encoding: "utf8",
  });
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function createFixture(name) {
  const fixtureRoot = path.join(scratchRoot, name, "godot-world");

  fs.rmSync(path.dirname(fixtureRoot), { recursive: true, force: true });
  fs.mkdirSync(path.join(fixtureRoot, "rules", "schema"), { recursive: true });
  fs.mkdirSync(path.join(fixtureRoot, "rules", "packages"), { recursive: true });
  fs.mkdirSync(path.join(fixtureRoot, "scenes"), { recursive: true });
  fs.mkdirSync(path.join(fixtureRoot, "scripts"), { recursive: true });

  fs.copyFileSync(schemaPath, path.join(fixtureRoot, "rules", "schema", "rule_package.schema.json"));

  return fixtureRoot;
}

after(() => {
  fs.rmSync(scratchRoot, { recursive: true, force: true });
});

test("repository validator wrapper succeeds on the checked-in project", () => {
  const result = spawnSync("bash", [wrapperPath], {
    cwd: repoRoot,
    encoding: "utf8",
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Repository validation passed\./);
  assert.match(result.stdout, /rule packages: \d+/);
});

test("repository validator reports schema violations clearly", () => {
  const fixtureRoot = createFixture("schema-violation");
  const packageData = JSON.parse(fs.readFileSync(packagePath, "utf8"));

  delete packageData.display_name;
  writeJson(path.join(fixtureRoot, "rules", "packages", "broken.rule.json"), packageData);

  const result = runValidator(["--root", fixtureRoot]);
  const output = `${result.stdout}\n${result.stderr}`;

  assert.notEqual(result.status, 0);
  assert.match(output, /broken\.rule\.json/);
  assert.match(output, /Missing required property 'display_name'\./);
});

test("repository validator rejects non-object schema roots", () => {
  const fixtureRoot = createFixture("schema-root-type");
  const packageData = JSON.parse(fs.readFileSync(packagePath, "utf8"));

  writeJson(path.join(fixtureRoot, "rules", "schema", "rule_package.schema.json"), []);
  writeJson(path.join(fixtureRoot, "rules", "packages", "time.rule.json"), packageData);

  const result = runValidator(["--root", fixtureRoot]);
  const output = `${result.stdout}\n${result.stderr}`;

  assert.notEqual(result.status, 0);
  assert.match(output, /rule_package\.schema\.json/);
  assert.match(output, /Schema must be a JSON object\./);
});

test("repository validator reports duplicate package ids clearly", () => {
  const fixtureRoot = createFixture("duplicate-package-id");
  const packageData = JSON.parse(fs.readFileSync(packagePath, "utf8"));

  writeJson(path.join(fixtureRoot, "rules", "packages", "time.rule.json"), packageData);
  writeJson(path.join(fixtureRoot, "rules", "packages", "time-copy.rule.json"), packageData);

  const result = runValidator(["--root", fixtureRoot]);
  const output = `${result.stdout}\n${result.stderr}`;

  assert.notEqual(result.status, 0);
  assert.match(output, /Duplicate package_id 'builtin\.time'; already defined in .*\.rule\.json\./);
  assert.match(output, /time\.rule\.json|time-copy\.rule\.json/);
});

test("repository validator reports unknown package dependencies clearly", () => {
  const fixtureRoot = createFixture("missing-package-dependency");
  const packageData = JSON.parse(fs.readFileSync(packagePath, "utf8"));

  packageData.package_dependencies = ["builtin.missing_dependency"];
  writeJson(path.join(fixtureRoot, "rules", "packages", "time.rule.json"), packageData);

  const result = runValidator(["--root", fixtureRoot]);
  const output = `${result.stdout}\n${result.stderr}`;

  assert.notEqual(result.status, 0);
  assert.match(output, /Unknown package dependency 'builtin\.missing_dependency'\./);
  assert.match(output, /\$\.package_dependencies\[0\]/);
});

test("repository validator enforces default package base capabilities", () => {
  const fixtureRoot = createFixture("default-package-capabilities");
  const defaultPackage = JSON.parse(fs.readFileSync(defaultPackagePath, "utf8"));
  const peacefulWorldOrder = JSON.parse(fs.readFileSync(peacefulWorldOrderPath, "utf8"));

  defaultPackage.runtime_contract.foundation_capabilities =
    defaultPackage.runtime_contract.foundation_capabilities.filter((capability) => capability !== "basic-action");
  writeJson(path.join(fixtureRoot, "rules", "packages", "default_package.rule.json"), defaultPackage);
  writeJson(path.join(fixtureRoot, "rules", "packages", "peaceful_world_order.rule.json"), peacefulWorldOrder);

  const result = runValidator(["--root", fixtureRoot]);
  const output = `${result.stdout}\n${result.stderr}`;

  assert.notEqual(result.status, 0);
  assert.match(output, /Default package runtime_contract\.foundation_capabilities must include 'basic-action'\./);
});

test("repository validator rejects world-order coupling to default-package rule kinds", () => {
  const fixtureRoot = createFixture("world-order-hard-coded-default-rule-kind");
  const defaultPackage = JSON.parse(fs.readFileSync(defaultPackagePath, "utf8"));
  const peacefulWorldOrder = JSON.parse(fs.readFileSync(peacefulWorldOrderPath, "utf8"));
  const foundationOperation = peacefulWorldOrder.patch.operations.find(
    (operation) => operation.rule_id === "world_order.peaceful_foundation"
  );

  foundationOperation.requires_rule_kinds = ["default-package.base"];
  writeJson(path.join(fixtureRoot, "rules", "packages", "default_package.rule.json"), defaultPackage);
  writeJson(path.join(fixtureRoot, "rules", "packages", "peaceful_world_order.rule.json"), peacefulWorldOrder);

  const result = runValidator(["--root", fixtureRoot]);
  const output = `${result.stdout}\n${result.stderr}`;

  assert.notEqual(result.status, 0);
  assert.match(output, /Peaceful world order must require world capabilities, not default-package-specific rule kinds\./);
});

test("repository validator reports broken ExtResource references clearly", () => {
  const fixtureRoot = createFixture("reference-violation");
  const packageData = JSON.parse(fs.readFileSync(packagePath, "utf8"));

  writeJson(path.join(fixtureRoot, "rules", "packages", "time.rule.json"), packageData);
  fs.writeFileSync(path.join(fixtureRoot, "scripts", "exists.gd"), "extends Node\n", "utf8");
  fs.writeFileSync(
    path.join(fixtureRoot, "scenes", "Main.tscn"),
    `[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/exists.gd" id="1_main"]

[node name="Main" type="Node"]
script = ExtResource("2_missing")
`,
    "utf8"
  );

  const result = runValidator(["--root", fixtureRoot]);
  const output = `${result.stdout}\n${result.stderr}`;

  assert.notEqual(result.status, 0);
  assert.match(output, /Main\.tscn/);
  assert.match(output, /ExtResource\("2_missing"\) does not match any \[ext_resource\] id\./);
});

test("repository validator rejects repository references that escape the project root", () => {
  const fixtureRoot = createFixture("reference-traversal");
  const packageData = JSON.parse(fs.readFileSync(packagePath, "utf8"));

  writeJson(path.join(fixtureRoot, "rules", "packages", "time.rule.json"), packageData);
  fs.writeFileSync(
    path.join(fixtureRoot, "scripts", "bad_reference.gd"),
    'extends Node\nconst BAD_REFERENCE = preload("res://../outside.gd")\n',
    "utf8"
  );

  const result = runValidator(["--root", fixtureRoot]);
  const output = `${result.stdout}\n${result.stderr}`;

  assert.notEqual(result.status, 0);
  assert.match(output, /bad_reference\.gd/);
  assert.match(output, /res:\/\/\.\.\/outside\.gd is not a valid repository reference\./);
});
