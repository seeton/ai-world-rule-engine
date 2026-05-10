# Contributing

## Default workflow

This repository uses **issue-driven development**:

1. Open or refine a GitHub issue before writing code.
2. Create a branch for that issue.
3. Implement the scoped change.
4. Open a PR linked to the issue.
5. Merge through PR review; do not merge direct-to-main changes by default.

If a PR depends on Copilot automatic review in this repository, do not merge it until that review has completed. If no automatic review is configured or available for the PR, call that out explicitly in the PR notes before merging.

`godot-world/` is the active Godot 4 project and the primary location for gameplay, runtime, and rule-package changes.

## Repo-root main checkout

Treat the repo-root `main` checkout as a sync-only baseline instead of a normal implementation workspace.

- do implementation, conflict resolution, and experiments in issue worktrees
- keep repo-root tracked files clean enough for fast-forward syncs
- if tracked changes or unmerged paths appear at repo root, move that work into the owning issue worktree before syncing
- intentional untracked local directories may remain, but they should not block repo-root syncs

Helper commands:

- `bash scripts/agent_guard.sh status` — includes repo-root tracked/untracked state
- `bash scripts/worktree.sh root-status` — prints only the repo-root checkout state
- `bash scripts/worktree.sh status --stale-days 14` — lists issue worktrees with issue state, dirty state, claim state, and stale status
- `bash scripts/worktree.sh sync-root` — fast-forwards the repo-root default branch when tracked files are clean

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
- do not add `@copilot レビューをお願いします` on the initial creation of a new PR; add it only when requesting another review pass on an existing PR after follow-up changes

Call out scope clearly:

- whether the PR touches `godot-world/`
- whether the PR stays within the intended `godot-world/` scope
- whether rule packages are new, cloned, or forks of existing packages

## Resolving stale or overlapping PRs

When you are fixing, reviewing, or deciding whether to keep an existing open PR, classify it before making more changes. Use exactly one of these states:

- `merge-ready` - the PR is current, scoped correctly, validated, and can merge as-is
- `needs-fix` - the PR should stay open, but it still needs conflict resolution, review fixes, or validation
- `superseded` - the useful change already landed elsewhere, so keeping the PR open adds confusion
- `split-required` - the PR mixes too many goals or stale integration work and should be replaced with smaller follow-up PRs
- `close` - the PR should not continue in its current form and has no unique value worth carrying forward

Record that classification and the rationale in the PR body, review thread, or linked issue comment before doing more cleanup. If multiple PRs touch the same area, explicitly name which PR is the current source of truth and which ones should close or be recreated.

Do not add `@copilot レビューをお願いします` when opening a brand-new PR for the first time. Add that comment only when an existing PR has follow-up changes and you want to request another review pass explicitly in the timeline.

Do not document helper scripts or workflow tooling unless that helper is tracked in the same branch/repository. If the repository does not contain the helper, document the real `git`, `godot`, or test commands directly.

## Merge decision gates

`mergeable=true` on GitHub only means the branch can merge mechanically. It is not enough on its own for this repository.

Before merging a PR that changes `godot-world/`, gameplay/runtime scripts, scenes, or rule-package data, the PR should include concrete evidence for the checks that matter to its scope:

- `git diff --check`
- a headless Godot startup command such as `godot --headless --path godot-world --quit-after 1`, or an equivalent command that actually exists in the branch being reviewed
- any parse/schema/contract checks relevant to the edited files
- confirmation that unresolved review threads were addressed or intentionally deferred

If a stale PR is being retired instead of merged, the closing comment should point to the replacement PR, merged commit, or issue comment that now owns the work.

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
