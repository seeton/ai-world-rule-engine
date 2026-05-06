# Contributing

## Default workflow

This repository uses **issue-driven development**:

1. Open or refine a GitHub issue before writing code.
2. Create or reuse a repo-local git worktree under `.agent-workspaces/issue-<number>/`.
3. Create the issue branch in that worktree, or reuse the existing issue branch when the worktree already exists.
4. Implement the scoped change.
5. Open a PR linked to the issue.
6. Merge through PR review; do not merge direct-to-main changes by default.
7. Close the issue through `bash scripts/close_issue.sh <issue-number>` from the repo root or another non-target worktree so local cleanup happens automatically.

`godot-world/` is the active Godot 4 project and the primary location for gameplay, runtime, and rule-package changes. Root-level changes should generally stay limited to repo docs, workflow metadata, or shared tooling.

## Repo-local worktree convention

Keep reusable contributor and agent workspaces inside the repository boundary:

- preferred location: `.agent-workspaces/issue-<number>/`
- prefer `scripts/worktree.sh ensure <issue-number> <branch-name>` from the repo root
- if you create it manually, use `git worktree add .agent-workspaces/issue-<number> -b <branch-name>`
- reuse the same worktree for follow-up commits on that issue across later runs when practical, but do not have multiple active sessions share it concurrently
- keep scratch notes, logs, and generated artifacts inside that worktree or other ignored repo-local paths
- do **not** create extra clones or checkouts under `/Users/seeton`, `~`, or other home-directory locations

This keeps parallel work visible, avoids stray home-directory clones, and makes cleanup predictable. `.agent-workspaces/` is gitignored and should remain uncommitted.

## Issue close and cleanup

- If an issue is ready to close, sync the repo root first with a clone/fetch/pull equivalent from the main repository context.
- `bash scripts/close_issue.sh <issue-number>` is the supported close path. It fetches `origin` from the repo root, fast-forward pulls the default branch when the repo root is already a clean checkout of that branch, closes the issue through `gh`, releases claims for `.agent-workspaces/issue-<number>`, and removes that repo-local worktree.
- Run the close helper from the repo root or another worktree, not from the worktree being removed.
- If the issue was closed outside the helper flow, run `bash scripts/cleanup_closed_worktrees.sh` or `bash scripts/close_issue.sh <issue-number>` afterward.

## Issue decomposition for multi-agent work

Use one tracking issue for the larger goal, then split implementation into independent child issues when possible.

- **Coordinator/lead**: owns the parent issue, defines scope boundaries, and tracks integration.
- **Implementation agents**: each take one issue, one branch, and one PR.
- Prefer decomposition by subsystem, for example:
  - Godot UI / scene work
  - simulation/runtime changes
  - rule package content
  - docs
- If two agents would touch the same files heavily, split the work differently or sequence it instead of running in parallel.

Each child issue should include:

- goal and non-goals
- files or folders expected to change
- validation steps
- dependencies on other issues/PRs

## Branch naming

Use branch names that map directly to an issue:

- `feat/<issue-number>-<short-slug>`
- `fix/<issue-number>-<short-slug>`
- `docs/<issue-number>-<short-slug>`
- `chore/<issue-number>-<short-slug>`

Examples:

- `feat/123-worldstate-events`
- `fix/145-runtime-threshold-effects`
- `docs/188-github-workflow`

## Pull request expectations

Every PR should be small enough to review and should include:

- linked issue(s)
- concise summary of the change
- validation performed
- risks, follow-ups, or explicitly deferred work
- screenshots/video for visible Godot changes when relevant

Call out scope clearly:

- whether the PR touches `godot-world/`
- whether the PR stays within the intended `godot-world/` scope
- whether rule packages are new, cloned, or forks of existing packages

## Playable handoff rules

When a change reaches a playable game state or completes a playable PoC slice:

- open a PR linked to the issue before handing the work off as complete
- include the exact game launch command(s) in the handoff note, not just prose instructions
- include any additional run context the reviewer needs, for example the working directory, Godot entry path, or required flags

Example launch commands for the active Godot project:

- `godot --path godot-world`
- `cd godot-world && godot`

## Multi-agent integration rules

- One agent per worktree branch/PR.
- Do not mix unrelated issue scopes in the same branch.
- Rebase or merge the latest target branch before final validation.
- The coordinator merges child PRs in dependency order, then closes the parent issue when integration is complete.
- Cross-agent fixes should go back through the owning issue/branch unless the coordinator explicitly folds them into an integration PR.

## Rule package contribution model

Rule packages in `godot-world/rules/packages/` follow a **clone / fork / upstream** model.

### Local package workflow

1. **Clone** an existing package when a mechanic already matches closely.
2. **Fork** it when you need a variant.
3. **Create from scratch** only when no existing package is a good base.

Preserve and update package metadata:

- `source_repo`
- `source_ref`
- `forked_from`
- `suggested_pr_target`

Expected conventions:

- built-in or upstream-aligned packages keep provenance intact
- variants record their parent in `forked_from`
- proposed upstream contributions set `suggested_pr_target`
- package patches stay declarative; do not add arbitrary code execution to package data

### Upstream contribution flow

When a local fork becomes generally useful:

1. open an issue describing why the variant should be shared upstream
2. implement it on an issue branch
3. open a PR with package metadata/provenance intact
4. note compatibility or migration impact for existing packages

See `godot-world/docs/rule_packages.md` for package-format details.
