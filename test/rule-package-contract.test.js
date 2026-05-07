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
  assert.equal(schemaRequired.has("rule_patch"), false, "Schema must not require legacy rule_patch.");
  assert.ok(repositoryRequiredKeys.includes("patch"), "Repository must require top-level patch.");
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
    assert.equal(typeof packageData.patch, "object", `${fileName} patch must be an object.`);
    assert.notEqual(packageData.patch, null, `${fileName} patch must not be null.`);
    assert.equal(Array.isArray(packageData.patch), false, `${fileName} patch must not be an array.`);
    assert.equal(packageIds.has(packageData.package_id), false, `Duplicate package_id ${packageData.package_id}.`);

    packageIds.add(packageData.package_id);
  }
});
