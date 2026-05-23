const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const repoRoot = path.resolve(__dirname, "..");
const schemaPath = path.join(repoRoot, "godot-world", "rules", "schema", "rule_package.schema.json");
const packageDirectory = path.join(repoRoot, "godot-world", "rules", "packages");
const repositoryPath = path.join(repoRoot, "godot-world", "scripts", "integration", "rule_package_repository.gd");

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function getPackageFilePaths() {
  return fs
    .readdirSync(packageDirectory)
    .filter((fileName) => fileName.endsWith(".rule.json"))
    .sort()
    .map((fileName) => path.join(packageDirectory, fileName));
}

function getRepositoryRequiredKeys() {
  const repositorySource = fs.readFileSync(repositoryPath, "utf8");
  const requiredKeysBlock = repositorySource.match(/var required_keys := \[(?<keys>[\s\S]*?)\r?\n\t\]/);

  assert.ok(requiredKeysBlock?.groups?.keys, "Failed to locate RulePackageRepository required_keys.");

  return [...requiredKeysBlock.groups.keys.matchAll(/"([^"]+)"/g)].map(([, key]) => key);
}

test("rule package schema and repository use patch as the canonical top-level field", () => {
  const schema = readJson(schemaPath);
  const schemaRequired = new Set(schema.required || []);
  const repositoryRequiredKeys = getRepositoryRequiredKeys();

  assert.ok(schemaRequired.has("patch"), "Schema must require top-level patch.");
  assert.ok(schemaRequired.has("package_dependencies"), "Schema must require package_dependencies.");
  assert.equal(schemaRequired.has("rule_patch"), false, "Schema must not require legacy rule_patch.");
  assert.ok(repositoryRequiredKeys.includes("patch"), "Repository must require top-level patch.");
  assert.ok(repositoryRequiredKeys.includes("package_dependencies"), "Repository must require package_dependencies.");
  assert.equal(repositoryRequiredKeys.includes("rule_patch"), false, "Repository must not accept legacy rule_patch.");
});

test("every built-in rule package satisfies the repository contract", () => {
  const repositoryRequiredKeys = getRepositoryRequiredKeys();
  const packageIds = new Set();
  const packageFilePaths = getPackageFilePaths();

  assert.ok(packageFilePaths.length > 0, "Expected built-in rule packages to exist.");

  for (const filePath of packageFilePaths) {
    const packageData = readJson(filePath);
    const fileName = path.basename(filePath);

    for (const key of repositoryRequiredKeys) {
      assert.notEqual(packageData[key], undefined, `${fileName} is missing required key ${key}.`);
    }

    assert.equal(Object.hasOwn(packageData, "rule_patch"), false, `${fileName} still uses legacy rule_patch.`);
    assert.equal(Array.isArray(packageData.package_dependencies), true, `${fileName} package_dependencies must be an array.`);
    assert.equal(typeof packageData.patch, "object", `${fileName} patch must be an object.`);
    assert.notEqual(packageData.patch, null, `${fileName} patch must not be null.`);
    assert.equal(Array.isArray(packageData.patch), false, `${fileName} patch must not be an array.`);
    assert.equal(packageIds.has(packageData.package_id), false, `Duplicate package_id ${packageData.package_id}.`);

    for (const operation of packageData.patch.operations || []) {
      if (operation?.op !== "upsert_rule") {
        continue;
      }
      assert.equal(
        typeof operation.player_description,
        "string",
        `${fileName} upsert_rule ${operation.rule_id} must include player_description.`
      );
      assert.notEqual(
        operation.player_description.trim(),
        "",
        `${fileName} upsert_rule ${operation.rule_id} must not leave player_description empty.`
      );
    }

    packageIds.add(packageData.package_id);
  }
});

test("default package and peaceful world order expose the split base contract", () => {
  const defaultPackage = readJson(path.join(packageDirectory, "default_package.rule.json"));
  const peacefulWorldOrder = readJson(path.join(packageDirectory, "peaceful_world_order.rule.json"));

  assert.deepEqual(defaultPackage.package_dependencies, []);
  assert.deepEqual(defaultPackage.runtime_contract.supports_world_modes, ["two_d", "three_d"]);
  assert.deepEqual(defaultPackage.runtime_contract.foundation_capabilities, [
    "existence",
    "representation",
    "state",
    "space",
    "base-time",
    "movement",
    "basic-action",
  ]);
  assert.ok(defaultPackage.runtime_contract.provides_capabilities.includes("world.foundation"));
  for (const capability of defaultPackage.runtime_contract.foundation_capabilities) {
    assert.ok(
      defaultPackage.runtime_contract.provides_capabilities.includes(`world.${capability}`),
      `default package must provide world.${capability}`
    );
  }
  assert.equal(defaultPackage.runtime_contract.lifecycle.immutable_engine_invariant, false);
  assert.equal(defaultPackage.runtime_contract.lifecycle.removable, true);
  assert.equal(defaultPackage.runtime_contract.lifecycle.disableable, true);
  assert.equal(defaultPackage.runtime_contract.lifecycle.replaceable, true);
  assert.equal(defaultPackage.runtime_contract.collapse_behavior.runtime_must_prevent_removal, false);

  assert.deepEqual(peacefulWorldOrder.package_dependencies, ["builtin.default_package"]);
  assert.deepEqual(peacefulWorldOrder.runtime_contract.supports_world_modes, ["two_d", "three_d"]);
  assert.ok(peacefulWorldOrder.runtime_contract.requires_capabilities.includes("world.foundation"));
  assert.ok(peacefulWorldOrder.runtime_contract.requires_capabilities.includes("world.base-time"));
  assert.ok(
    peacefulWorldOrder.patch.operations.some(
      (operation) =>
        operation.rule_id === "world_order.peaceful_foundation" &&
        Array.isArray(operation.requires_rule_kinds) &&
        operation.requires_rule_kinds.includes("world.foundation")
    ),
    "peaceful world order should depend on the world foundation capability."
  );
  assert.equal(
    peacefulWorldOrder.patch.operations.some((operation) =>
      (operation.requires_rule_kinds || []).some((ruleKind) => ruleKind.startsWith("default-package."))
    ),
    false,
    "peaceful world order should not require default-package-specific rule kinds."
  );
});

test("schema documents mutable runtime contract fields", () => {
  const schema = readJson(schemaPath);
  const runtimeContract = schema.properties.runtime_contract.properties;

  for (const key of ["provides_capabilities", "requires_capabilities", "lifecycle", "collapse_behavior", "replacement_contract", "engine_safety_shell"]) {
    assert.ok(runtimeContract[key], `runtime_contract must describe ${key}`);
  }
  assert.ok(runtimeContract.lifecycle.properties.removable);
  assert.ok(runtimeContract.lifecycle.properties.disableable);
  assert.ok(runtimeContract.lifecycle.properties.replaceable);
  assert.ok(runtimeContract.collapse_behavior.properties.runtime_must_prevent_removal);
});
