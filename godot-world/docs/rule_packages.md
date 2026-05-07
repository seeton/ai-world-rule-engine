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

Use package changes with the same default workflow as the rest of the repo: **issue → branch → PR**.

- clone an existing package when the mechanic already fits
- fork it when you need a variant and set `forked_from`
- preserve `source_repo` and `source_ref`
- set `suggested_pr_target` when the package should be proposed upstream

Before opening a PR, run `bash godot-world/scripts/validate_repo.sh` from the repository root. It validates package JSON against the checked-in schema and catches static `res://...` / `ExtResource(...)` mistakes without requiring a local Godot install, but it does require Python 3 because the wrapper invokes `python3`.

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
