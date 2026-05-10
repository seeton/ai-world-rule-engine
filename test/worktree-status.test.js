const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const { after, test } = require("node:test");

const repoRoot = path.resolve(__dirname, "..");
const worktreeScriptPath = path.join(repoRoot, "scripts", "worktree.sh");
const scratchRoot = path.join(repoRoot, "test", ".scratch", "worktree-status");
const statusHeader =
  "ISSUE\tISSUE_STATE\tGIT_STATE\tCLAIM_STATE\tPR_CLAIMS\tSTALE\tAGE_DAYS\tLAST_UPDATED\tBRANCH\tPATH\tSTATUS";

function run(command, args, options = {}) {
  return spawnSync(command, args, {
    encoding: "utf8",
    ...options,
  });
}

function makeExecutable(filePath, contents) {
  fs.writeFileSync(filePath, contents, { encoding: "utf8", mode: 0o755 });
}

function createFixture(name, options = {}) {
  const { withWorktrees = true, gnuOnlyCoreutils = false } = options;
  const fixtureRoot = path.join(scratchRoot, name);
  const repoPath = path.join(fixtureRoot, "repo");
  const fakeBinPath = path.join(fixtureRoot, "bin");
  const scriptsPath = path.join(repoPath, "scripts");
  const coordPath = path.join(repoPath, ".agent-workspaces", ".coord");
  const issueOnePath = path.join(repoPath, ".agent-workspaces", "issue-1");
  const issueTwoPath = path.join(repoPath, ".agent-workspaces", "issue-2");

  fs.rmSync(fixtureRoot, { recursive: true, force: true });
  fs.mkdirSync(scriptsPath, { recursive: true });
  fs.mkdirSync(fakeBinPath, { recursive: true });
  fs.mkdirSync(path.join(coordPath, "issues"), { recursive: true });
  fs.mkdirSync(path.join(coordPath, "prs"), { recursive: true });

  fs.copyFileSync(worktreeScriptPath, path.join(scriptsPath, "worktree.sh"));
  fs.writeFileSync(path.join(repoPath, "README.md"), "# fixture\n", "utf8");

  run("git", ["init", "-b", "main"], { cwd: repoPath });
  run("git", ["config", "user.name", "Copilot Test"], { cwd: repoPath });
  run("git", ["config", "user.email", "copilot-test@example.com"], { cwd: repoPath });
  run("git", ["add", "."], { cwd: repoPath });
  run("git", ["commit", "-m", "init"], { cwd: repoPath });

  if (withWorktrees) {
    run("git", ["worktree", "add", "-b", "feat/1", issueOnePath, "HEAD"], { cwd: repoPath });
    run("git", ["worktree", "add", "-b", "feat/2", issueTwoPath, "HEAD"], { cwd: repoPath });

    fs.writeFileSync(path.join(issueTwoPath, "dirty.txt"), "dirty\n", "utf8");

    fs.writeFileSync(path.join(coordPath, "issues", "2.claim"), `${issueTwoPath}\n`, "utf8");
    fs.writeFileSync(path.join(coordPath, "prs", "99.claim"), `${issueTwoPath}\n`, "utf8");
  }

  makeExecutable(
    path.join(fakeBinPath, "gh"),
    `#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "issue" && "$2" == "view" ]]; then
  case "$3" in
    1) printf 'CLOSED\\n' ;;
    2) printf 'OPEN\\n' ;;
    *) printf 'UNKNOWN\\n' ;;
  esac
  exit 0
fi
echo "unexpected gh invocation: $*" >&2
exit 1
`
  );

  if (gnuOnlyCoreutils) {
    makeExecutable(
      path.join(fakeBinPath, "stat"),
      `#!/usr/bin/env node
const args = process.argv.slice(2);
if (args[0] === "-c" && args[1] === "%Y" && /\\/issue-2\\/dirty\\.txt$/.test(args[2] || "")) {
  console.log("2000000000");
  process.exit(0);
}
process.exit(1);
`
    );

    makeExecutable(
      path.join(fakeBinPath, "date"),
      `#!/usr/bin/env node
const args = process.argv.slice(2);
if (args.length === 1 && args[0] === "+%s") {
  console.log("3000000000");
  process.exit(0);
}
if (
  args[0] === "-u" &&
  args[1] === "-d" &&
  /^@\\d+$/.test(args[2] || "") &&
  args[3] === "+%Y-%m-%dT%H:%M:%SZ"
) {
  const epoch = Number(args[2].slice(1));
  console.log(new Date(epoch * 1000).toISOString().replace(".000Z", "Z"));
  process.exit(0);
}
process.exit(1);
`
    );
  }

  return { repoPath, issueOnePath, issueTwoPath, fakeBinPath };
}

function parseStatusOutput(stdout) {
  const lines = stdout.trim().split("\n");
  assert.equal(lines[1], statusHeader);
  const rows = new Map();

  for (const line of lines.slice(2)) {
    const columns = line.split("\t");
    rows.set(columns[0], {
      issue: columns[0],
      issueState: columns[1],
      gitState: columns[2],
      claimState: columns[3],
      prClaims: columns[4],
      stale: columns[5],
      ageDays: columns[6],
      lastUpdated: columns[7],
      branch: columns[8],
      path: columns[9],
      status: columns[10],
    });
  }

  return rows;
}

after(() => {
  fs.rmSync(scratchRoot, { recursive: true, force: true });
});

test("worktree status reports issue, git, claim, and PR status", () => {
  const { repoPath, issueOnePath, issueTwoPath, fakeBinPath } = createFixture("status-report");
  const result = run("bash", ["scripts/worktree.sh", "status", "--stale-days", "99999"], {
    cwd: repoPath,
    env: {
      ...process.env,
      PATH: `${fakeBinPath}:${process.env.PATH}`,
    },
  });

  assert.equal(result.status, 0, result.stderr);
  const rows = parseStatusOutput(result.stdout);

  assert.deepEqual(rows.get("1"), {
    issue: "1",
    issueState: "CLOSED",
    gitState: "clean",
    claimState: "unclaimed",
    prClaims: "-",
    stale: "fresh",
    ageDays: rows.get("1").ageDays,
    lastUpdated: rows.get("1").lastUpdated,
    branch: "feat/1",
    path: issueOnePath,
    status: "closed-clean",
  });

  assert.equal(rows.get("2").issueState, "OPEN");
  assert.equal(rows.get("2").gitState, "dirty");
  assert.equal(rows.get("2").claimState, "claimed");
  assert.equal(rows.get("2").prClaims, "99");
  assert.equal(rows.get("2").stale, "fresh");
  assert.equal(rows.get("2").branch, "feat/2");
  assert.equal(rows.get("2").path, issueTwoPath);
  assert.equal(rows.get("2").status, "open-dirty-claimed");
});

test("worktree status respects the stale threshold", () => {
  const { repoPath, fakeBinPath } = createFixture("stale-threshold");
  const result = run("bash", ["scripts/worktree.sh", "status", "--stale-days", "0"], {
    cwd: repoPath,
    env: {
      ...process.env,
      PATH: `${fakeBinPath}:${process.env.PATH}`,
    },
  });

  assert.equal(result.status, 0, result.stderr);
  const rows = parseStatusOutput(result.stdout);
  assert.equal(rows.get("1").stale, "stale");
  assert.equal(rows.get("2").stale, "stale");
  assert.match(rows.get("1").status, /-stale$/);
  assert.match(rows.get("2").status, /-stale$/);
});

test("worktree status supports GNU stat/date syntax", () => {
  const { repoPath, fakeBinPath } = createFixture("gnu-coreutils", { gnuOnlyCoreutils: true });
  const result = run("bash", ["scripts/worktree.sh", "status", "--stale-days", "99999"], {
    cwd: repoPath,
    env: {
      ...process.env,
      PATH: `${fakeBinPath}:${process.env.PATH}`,
    },
  });

  assert.equal(result.status, 0, result.stderr);
  const rows = parseStatusOutput(result.stdout);
  assert.equal(rows.get("2").lastUpdated, "2033-05-18T03:33:20Z");
  assert.equal(rows.get("2").ageDays, "11574");
});

test("worktree status keeps stdout machine-readable when no worktrees exist", () => {
  const { repoPath, fakeBinPath } = createFixture("no-worktrees", { withWorktrees: false });
  const result = run("bash", ["scripts/worktree.sh", "status"], {
    cwd: repoPath,
    env: {
      ...process.env,
      PATH: `${fakeBinPath}:${process.env.PATH}`,
    },
  });

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, `stale_days=14\n${statusHeader}\n`);
  assert.match(result.stderr, /No repo-local issue worktrees found under/);
});
