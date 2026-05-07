# Contributing

## Default workflow

This repository uses **issue-driven development**:

1. Open or refine a GitHub issue before writing code.
2. Create a branch for that issue.
3. Implement the scoped change.
4. Open a PR linked to the issue.
5. Merge through PR review; do not merge direct-to-main changes by default.

If a PR depends on Copilot automatic review in this repository, do not merge it until that review has completed. If no automatic review is configured or available for the PR, call that out explicitly in the PR notes before merging.

`godot-world/` is the active Godot 4 project. The root Node app is an older PoC and should remain intact unless an issue explicitly calls for changes there.

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
- whether Copilot automatic review completed, or that no automatic review was available/configured

Call out scope clearly:

- whether the PR touches `godot-world/`
- whether the legacy Node PoC was intentionally left unchanged
- whether rule packages are new, cloned, or forks of existing packages

## Multi-agent integration rules

- One agent per branch/PR.
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
