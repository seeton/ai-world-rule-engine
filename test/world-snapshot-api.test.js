const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const repoRoot = path.resolve(__dirname, "..");
const godotProjectPath = path.join(repoRoot, "godot-world");
const worldStatePath = path.join(godotProjectPath, "scripts", "core", "WorldState.gd");
const runtimePath = path.join(godotProjectPath, "scripts", "core", "SimulationRuntime.gd");
const readmePath = path.join(godotProjectPath, "README.md");
const smokeScriptPath = "res://scripts/tests/world_snapshot_smoke_test.gd";

function canRun(command) {
  if (!command) {
    return false;
  }

  const result = childProcess.spawnSync(command, ["--version"], {
    encoding: "utf8",
    timeout: 30000,
  });

  return !result.error && result.status === 0;
}

function findGodotExecutable() {
  const candidates = [process.env.GODOT_BIN, "godot", "/opt/homebrew/bin/godot"];

  for (const candidate of candidates) {
    if (canRun(candidate)) {
      return candidate;
    }
  }

  return null;
}

test("WorldState exposes save/load snapshot APIs and README documents the format", () => {
  const worldStateSource = fs.readFileSync(worldStatePath, "utf8");
  const runtimeSource = fs.readFileSync(runtimePath, "utf8");
  const readmeSource = fs.readFileSync(readmePath, "utf8");

  assert.match(worldStateSource, /func create_world_snapshot\(\) -> Dictionary:/);
  assert.match(worldStateSource, /func restore_world_snapshot\(snapshot_data: Dictionary\) -> Dictionary:/);
  assert.match(worldStateSource, /func save_world_snapshot\(file_path: String\) -> Dictionary:/);
  assert.match(worldStateSource, /func load_world_snapshot\(file_path: String\) -> Dictionary:/);

  assert.match(runtimeSource, /const WORLD_SNAPSHOT_TYPE := "godot_world_state_snapshot"/);
  assert.match(runtimeSource, /func create_snapshot\(\) -> Dictionary:/);
  assert.match(runtimeSource, /func restore_snapshot\(snapshot_data: Dictionary\) -> Dictionary:/);
  assert.match(runtimeSource, /func save_snapshot\(file_path: String\) -> Dictionary:/);
  assert.match(runtimeSource, /func load_snapshot\(file_path: String\) -> Dictionary:/);

  assert.match(readmeSource, /`create_world_snapshot\(\) -> Dictionary`/);
  assert.match(readmeSource, /## Snapshot save format/);
  assert.match(readmeSource, /## Snapshot limitations/);
});

const godotExecutable = findGodotExecutable();

test(
  "world snapshot APIs round-trip installed rules and character values",
  { skip: godotExecutable ? undefined : "Godot executable not available" },
  () => {
    const result = childProcess.spawnSync(
      godotExecutable,
      ["--headless", "--path", godotProjectPath, "--script", smokeScriptPath],
      {
        cwd: repoRoot,
        encoding: "utf8",
        timeout: 120000,
      },
    );

    assert.equal(
      result.status,
      0,
      `Godot snapshot smoke test failed.\nSTDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}`,
    );
  },
);
