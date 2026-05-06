# Godot World Rule Packages

This folder contains a data-driven rule package workflow for a Godot 4 simulation game.

## Goals

- Reuse common mechanics by cloning a structured package from a library.
- Draft brand-new mechanics from player ideas without executing arbitrary code.
- Preserve GitHub-style package metadata so packages can later be forked, liked, disliked, and proposed upstream.

## Main folders

- `rules/schema/` — JSON schema-style contract for safe rule packages.
- `rules/packages/` — built-in reusable mechanics.
- `scripts/integration/` — repository and compiler helpers for Godot-side integration.
- `docs/` — workflow notes for clone/fork/PR behavior.

## Safety model

Rule packages only contain structured patch operations such as:

- `upsert_stat`
- `upsert_rule`
- `add_event_binding`
- `add_relation`

Packages do **not** execute embedded scripts or arbitrary code. The compiler produces structured draft patches that must be reviewed before being applied to the simulation.

## Core simulation foundation

- Runtime choice: **Godot 4 desktop**
- Autoload singleton: `scripts/core/WorldState.gd`
- Runtime model: `scripts/core/SimulationRuntime.gd`
- Rule package catalog: `rules/packages/*.rule.json` via `scripts/integration/`
- Optional bootstrap scene: `scenes/Bootstrap.tscn`

The core foundation starts from a null world with a mutable origin entity. Rules are additive data patches: AI proposes them, and the deterministic fixed-step runtime executes them without arbitrary code execution.

## Desktop shell workflow

The current Godot entry point is the desktop shell in `scenes/Main.tscn`.

- submit a natural-language task from the **Player Task** panel
- install a template package when a reusable mechanic already exists
- inspect installed rules and world/object state
- advance simulation time with **Advance Tick**

This is the baseline PoC2 workflow and remains available.

## Parallel 3D PoC

The project also tracks a **parallel 3D PoC** alongside the simpler PoC2 desktop shell. It is an additional visualization path, not a replacement for the existing inspector-heavy flow.

- the desktop shell is the expected place for a 3D preview capability to appear beside the current text/tree inspectors
- characters and the GM are visualized as simple box-like 3D placeholders in this PoC
- a `light` rule is used to demonstrate visible shadows
- a `gravity` rule is used to demonstrate falling objects

Expected exploration flow stays aligned with the current shell:

1. launch the Godot desktop shell
2. submit a task asking for a 3D view or for rules such as light/gravity
3. inspect the resulting world snapshot/rules and, when available, the 3D preview
4. advance ticks to observe rule-driven visual changes such as shadows or falling motion

If a requested mechanic does not already map to a built-in package, it should still follow the existing safe rule-package/draft workflow rather than bypassing the data-driven runtime model.

### WorldState API

- `submit_player_task(task_text: String) -> Dictionary`
- `clone_rule(rule_id: String) -> Dictionary`
- `create_rule_from_patch(rule_patch: Dictionary) -> Dictionary`
- `get_world_snapshot() -> Dictionary`
- `save_world_snapshot(file_path: String = "user://world_snapshot.json") -> Dictionary`
- `load_world_snapshot(file_path: String = "user://world_snapshot.json") -> Dictionary`
- `restore_world_snapshot(snapshot: Dictionary) -> Dictionary`
- `get_available_rule_packages() -> Array`
- `get_available_rule_templates() -> Array` (compatibility alias for legacy callers still expecting template terminology)
- `advance_tick(delta_seconds: float) -> void`

### Snapshot persistence and compatibility

`get_world_snapshot()` is the public/exported snapshot shape. `save_world_snapshot()` writes that exact dictionary as pretty-printed JSON, defaulting to `user://world_snapshot.json`; relative paths are resolved under `user://`. `load_world_snapshot()` is the disk entry point and forwards parsed JSON to `restore_world_snapshot()`, while `restore_world_snapshot()` is the in-memory restore path for snapshots already held by the UI, tests, or tooling.

The snapshot payload includes the canonical world state needed to restore a run:

- `world_id`, `world_name`, `runtime_choice`
- `elapsed_seconds`, `tick_index`, `fixed_step_seconds`
- `concepts`, `entities`, `player_task_history`, `event_log`
- installed rules in both map form (`installed_rules_by_id`) and sorted list form (`installed_rules`)

It also includes derived/debug-friendly fields that are safe to display or persist but are not required for restore:

- `snapshot_format_version`
- `tick` as a compatibility alias for `tick_index`
- `characters` and `events` summary arrays for the desktop shell
- `available_template_ids` and `available_rule_packages`
- `accumulator_seconds` and `clone_sequence`

Compatibility expectations:

- `SimulationRuntime.SNAPSHOT_FORMAT_VERSION` is the compatibility gate for persisted snapshots.
- If `snapshot_format_version` is present, restore only accepts the current version value.
- If `snapshot_format_version` is absent, restore treats the payload as a legacy/export snapshot and still accepts it as long as the canonical world-state fields are usable.
- Restore rebuilds runtime state from the canonical fields and ignores derived export-only fields such as `characters`, `events`, and `available_rule_packages`.
- Any incompatible change to the canonical restorable schema should bump `SNAPSHOT_FORMAT_VERSION` and update restore logic so snapshots produced by `get_world_snapshot()` / `save_world_snapshot()` continue to round-trip intentionally.

Recommended contributor workflow:

1. Use `get_world_snapshot()` when you need an inspectable/exportable world dump.
2. Use `save_world_snapshot()` when you want that same export written to disk for a later session.
3. Use `load_world_snapshot()` for normal file-based restore flows.
4. Use `restore_world_snapshot()` only when the snapshot dictionary is already in memory and you want the same normalization/version checks without going through the filesystem.

## Current bootstrap status

- `project.godot` boots `res://scenes/Main.tscn` and autoloads `res://scripts/core/WorldState.gd`.
- `scenes/Main.tscn` is a desktop shell for submitting tasks, reviewing/editing proposed rule packages, approving installs, installing rule packages, cloning installed rules, and manually advancing ticks.
- `scripts/core/WorldState.gd` loads `rules/packages/*.rule.json`, resolves player tasks through `scripts/integration/rule_compiler.gd`, and compiles installable runtime patches through `scripts/integration/runtime_rule_patch_compiler.gd`.
- `scenes/Bootstrap.tscn` is a minimal non-UI bootstrap scene that only advances `WorldState` every frame; it is useful for inspection but is **not** the configured default scene.

## Manual local run / inspection

1. Install Godot 4.2 locally. Godot is **not installed** in this repository's current automation environment, so the steps below are manual-only for now.
2. Open `godot-world/project.godot` in the Godot editor, or run the project from the repo root with `godot4 --path godot-world` (use `godot` instead if that is your local binary name).
3. Run the default project scene and confirm the shell status line reports `Data source: WorldState autoload`, not `fallback preview`.
4. Submit a task such as `add hunger`, confirm the Proposal Review panel surfaces `builtin.hunger` metadata, approve or install it from the review flow, and advance a few ticks to verify the world snapshot and event log update.
5. Submit a custom task with no strong match, edit the generated draft package JSON in the Proposal Review panel, approve it, and then install it. Confirm the panel blocks invalid JSON or changed-after-approval drafts until they are fixed and re-approved.
6. To inspect the bootstrap loop directly, run `res://scenes/Bootstrap.tscn` from the editor; it should tick the autoloaded `WorldState` without the desktop shell UI.

## Repository validation

Run the repository validator before opening or updating a PR that changes rule packages, the package schema, `project.godot`, scenes, or GDScript files with `res://` references.

- From `godot-world/`, run `./scripts/validate_repo.sh`
- From the repo root or another checkout, run `python3 godot-world/scripts/validate_repo.py --root godot-world`

This is the repeatable repo-level check for both Godot world changes and rule package changes. It verifies that:

- every `rules/packages/*.rule.json` file is valid JSON and matches `rules/schema/rule_package.schema.json`
- `package_id` values stay unique, package filenames match their `package_id`, and repository packages keep `suggested_pr_target.package_id` aligned with `package_id`
- static `res://` references in `project.godot`, `scenes/**/*.tscn`, and `scripts/**/*.gd` point to files that exist
- `.tscn` files only use `ExtResource(...)` ids that are declared in the same scene

Important constraints:

- the validator is static; it does not open the Godot editor, import assets, or run gameplay
- dynamic loads, `user://` paths, and runtime-only behavior still need manual Godot verification when relevant
- use this validator instead of re-checking individual packages by hand so package-only and broader project changes follow the same PR gate

## Known limitations and remaining risks

- Because Godot is not installed in this local environment, project import, scene loading, and runtime execution could not be re-verified here.
- `scripts/ui/main_desktop.gd` intentionally falls back to a preview snapshot when `/root/WorldState` is unavailable. The UI can still render in that mode, so manual validation must confirm the status line says `WorldState autoload`.
- `scripts/integration/runtime_rule_patch_compiler.gd` currently converts only `upsert_stat` operations and `upsert_rule` entries with `rule_type = "tick_delta"` into live runtime effects. Other package operations are preserved as `deferred_operations` and still need future runtime support.
- Generated custom packages still carry `review_status = "needs_design_review"` and should be treated as review artifacts until a designer/runtime pass turns them into approved gameplay changes.

### Desktop inspector (PoC2)

`scripts/ui/main_desktop.gd` now derives richer presentation directly from `get_world_snapshot()` data.

- Installed rules keep the flat list + raw JSON view and add a dependency tree derived client-side from snapshot metadata.
- If rules expose `resolved_parent_rule_ids`, the tree nests children under their resolved parents.
- If parent links are still unresolved, the tree falls back to `requires_rule_kinds` / `provides_rule_kinds` and calls out unmet required parent kinds.
- The world panel now groups character-style entities vs object-style entities and surfaces common ownership/containment fields such as `owner_id`, `container_id`, `location_id`, and `contained_entity_ids`.

### 3D preview runtime contract

The runtime can also expose an optional preview payload at `snapshot["three_d_preview"]` for a separate 3D renderer path.

- `enabled` — whether 3D preview rendering should be active.
- `renderables` — deterministic box-style entity data with `id`, `name`, `kind`, `is_character`, `is_gm`, `position`, `size`, `color`, plus optional `physics` / `state`.
- `lighting` — preview light settings including `enabled`, `shadows_enabled`, and `light_rotation_degrees`.
- `gravity` — preview gravity settings including `enabled` and `floor_y`; dynamic entities can fall over runtime ticks.
- `camera` — optional camera hint for the preview scene.
