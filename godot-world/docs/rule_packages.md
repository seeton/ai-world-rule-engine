# Rule package workflow

## Package format

Each package is a JSON document with:

- `package_id`
- `display_name`
- `description`
- `version`
- `author`
- `source_repo`
- `source_ref`
- `forked_from`
- `suggested_pr_target`
- `tags`
- `match_phrases`
- `community`
- `patch`

The `patch` block is intentionally limited to structured operations. This keeps the AI rule compiler safe and reviewable.

## Player workflow

### 1. Clone an existing package

When a player asks for a common mechanic such as hunger or sleep, the repository scores built-in packages by `tags` and `match_phrases`. If a strong match exists, the compiler returns a `clone_candidate` response with package metadata for future GitHub-style flows.

### 2. Draft a new mechanic

If no strong package matches, or the player explicitly wants a new variant, the compiler returns a `draft_custom_rule_patch` response. That draft:

- uses the same safe package format
- includes generated metadata
- sets `review_status` to `needs_design_review`
- can optionally point to `forked_from`
- can carry a `suggested_pr_target` for future upstream submission

### 2a. Desktop shell review flow

`res://scripts/ui/main_desktop.gd` now treats the latest task proposal as an editable review artifact:

- the Proposal Review panel shows clone/fork metadata, source repo/ref, and suggested upstream PR targets
- the package JSON is editable before install
- the shell requires a local approval step before install when the edited draft changes
- invalid JSON and changed-after-approval drafts are blocked until the player fixes and re-approves them
- deferred operations remain visible during review so the player knows which parts will not apply directly at runtime today

### 3. Social workflow

Packages support community metadata:

- `likes`
- `dislikes`
- `alternative_package_ids`

This allows a player to:

1. like or dislike an existing package
2. create an alternative package
3. record that alternative as a fork/variant
4. later submit the result upstream using `suggested_pr_target`

## Example metadata for GitHub-style sync

```json
{
  "package_id": "builtin.hunger",
  "source_repo": "github.com/godot-world/rule-library",
  "source_ref": "refs/heads/main",
  "author": "Godot World Team",
  "version": "1.0.0",
  "forked_from": null,
  "suggested_pr_target": {
    "repo": "github.com/godot-world/rule-library",
    "base_ref": "main",
    "package_id": "builtin.hunger"
  }
}
```

## GitHub contribution model

Use package changes with the same default workflow as the rest of the repo: **issue → repo-local worktree → branch → PR**.

- create or reuse `.agent-workspaces/<issue-or-scope>/` before editing package data
- use `git worktree add .agent-workspaces/<issue-or-scope> -b <branch-name>` when the worktree does not already exist
- reuse that worktree for follow-up commits on the same issue when practical
- do not create extra clones or checkouts in `/Users/seeton`, `~`, or other home-directory paths
- clone an existing package when the mechanic already fits
- fork it when you need a variant and set `forked_from`
- preserve `source_repo` and `source_ref`
- set `suggested_pr_target` when the package should be proposed upstream

Before opening or updating a rule package PR, run the shared repo validator from `godot-world/` with `./scripts/validate_repo.sh`. It is the required package check for this project: it validates package JSON against `rules/schema/rule_package.schema.json`, enforces package metadata invariants such as filename and `package_id` alignment, and also catches broken static Godot references that package work can accidentally introduce elsewhere in the project. Use `python3 scripts/validate_repo.py --root <path-to-godot-world>` when validating another checkout or worktree.

For rule package PRs, include:

- the linked issue
- whether the package is new, cloned, or forked
- review notes for gameplay impact
- any follow-up upstream PR target

## Safety notes

- No package contains embedded GDScript.
- The compiler only emits declarative patch operations.
- Human review is expected before a custom draft is merged into gameplay.

## Current runtime bridge

`res://scripts/integration/runtime_rule_patch_compiler.gd` compiles the safe package format into the current simulation runtime's simpler `rule_patch` shape without modifying core systems.

- `upsert_stat` compiles into baseline runtime effects with defaults and bounds
- `upsert_rule` with `rule_type = "tick_delta"` compiles into `value_per_second`
- event-driven, threshold, and environment operations are preserved as `deferred_operations` for future core support
