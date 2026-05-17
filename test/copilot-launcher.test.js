const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const { after, test } = require("node:test");

const repoRoot = path.resolve(__dirname, "..");
const launcherPath = path.join(repoRoot, "scripts", "launch_copilot.sh");
const scratchRoot = path.join(repoRoot, "test", ".scratch", "copilot-launcher");

function run(command, args, options = {}) {
  return spawnSync(command, args, {
    encoding: "utf8",
    ...options,
  });
}

function makeExecutable(filePath, contents) {
  fs.writeFileSync(filePath, contents, { encoding: "utf8", mode: 0o755 });
}

function createFixture(name) {
  const fixtureRoot = path.join(scratchRoot, name);
  const repoPath = path.join(fixtureRoot, "repo");
  const scriptsPath = path.join(repoPath, "scripts");
  const fakeBinPath = path.join(fixtureRoot, "bin");

  fs.rmSync(fixtureRoot, { recursive: true, force: true });
  fs.mkdirSync(scriptsPath, { recursive: true });
  fs.mkdirSync(fakeBinPath, { recursive: true });

  fs.copyFileSync(launcherPath, path.join(scriptsPath, "launch_copilot.sh"));
  fs.writeFileSync(path.join(repoPath, "README.md"), "# fixture\n", "utf8");

  makeExecutable(
    path.join(fakeBinPath, "copilot"),
    `#!/usr/bin/env node
console.log(JSON.stringify(process.argv.slice(2)));
`
  );

  return { repoPath, fakeBinPath };
}

after(() => {
  fs.rmSync(scratchRoot, { recursive: true, force: true });
});

test("Copilot launcher prepends repository defaults", () => {
  const { repoPath, fakeBinPath } = createFixture("defaults");
  const result = run("bash", ["scripts/launch_copilot.sh"], {
    cwd: repoPath,
    env: {
      ...process.env,
      PATH: `${fakeBinPath}:${process.env.PATH}`,
    },
  });

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout.trim()), ["--model", "gpt-5.4", "--effort", "high", "--allow-all"]);
});

test("Copilot launcher forwards extra arguments after the defaults", () => {
  const { repoPath, fakeBinPath } = createFixture("passthrough");
  const result = run(
    "bash",
    ["scripts/launch_copilot.sh", "--", "--continue", "--model", "gpt-5-mini", "--no-color"],
    {
      cwd: repoPath,
      env: {
        ...process.env,
        PATH: `${fakeBinPath}:${process.env.PATH}`,
      },
    }
  );

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout.trim()), [
    "--model",
    "gpt-5.4",
    "--effort",
    "high",
    "--allow-all",
    "--continue",
    "--model",
    "gpt-5-mini",
    "--no-color",
  ]);
});
