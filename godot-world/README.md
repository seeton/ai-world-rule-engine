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

## Repository validation

Contributors can validate rule package data and static Godot file references without installing Godot. You do need a Python 3 interpreter available on your shell `PATH` as `python3`, because the wrapper invokes that command directly.

Run this from the repository root inside your issue worktree:

```bash
bash godot-world/scripts/validate_repo.sh
```

The validator checks:

- every `rules/packages/*.rule.json` file against `rules/schema/rule_package.schema.json`
- duplicate package IDs and invalid JSON payloads
- static `res://...` paths plus `.tscn` `ExtResource(...)` wiring in `project.godot`, `scenes/`, and `scripts/`

If you also changed repository-side tests or rule package contracts, follow it with `node --test` from the repository root before opening a PR.

## World Operation API

Per #106, every surface that mutates the world (CLI, GUI, GM, Codex, automation) goes through the same World Operation API in `scripts/world_ops/`. CLI string syntax / GUI buttons / GM proposals are all just adapters that build a `{ operation_type, request }` and dispatch through `scripts/world_ops/dispatcher.gd`. See [`docs/world_operations.md`](docs/world_operations.md) for the operation catalog, result schema, and validate / dry_run / execute contract.

## Collapse-safe CLI

If the in-game UI or GM dialog becomes unresponsive (for example after a world rule collapse or `builtin.space` disable), use the headless rule-engine CLI as a last-line-of-defense control surface. See [`docs/cli.md`](docs/cli.md). Invoke it from an issue worktree via `bash scripts/world_cli.sh <issue-number> -- <subcommand>`; the wrapper refuses repo-root invocations.

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
- Template catalog: `scripts/core/RuleTemplates.gd`
- Optional bootstrap scene: `scenes/Bootstrap.tscn`

The core foundation starts from a null world with a mutable origin entity. Rules are additive data patches: AI proposes them, and the deterministic fixed-step runtime executes them without arbitrary code execution.

## Rule model

- Rules form a directed acyclic parent/child prerequisite graph (DAG) rather than a strict tree.
- Rules with no prerequisites act as root rules.
- A child rule may depend on one or more parent rules.
- A child rule only applies after all of its parent rules are already active.
- Required parent prerequisites cannot be skipped when applying child rules.
- Deeper descendants can sit behind multiple parent chains in the same graph.
- Every rule always owns a `Representation`, even when that representation is intentionally not visible in the world.
- Visible rules such as time use their `Representation` for rendering, while invisible rules such as gravity still keep an internal `Representation` so systems can treat all rules consistently.

See `docs/rule_model.md` for the detailed rule and representation invariants.

## Playable main scene (PoC3)

The current Godot entry point in `scenes/Main.tscn` starts in a playable 2D world and switches to the playable 3D world after the GM applies `3D化`.

### Launching from an issue worktree

Launch Godot from the issue-specific worktree instead of validating against the repo-root checkout.

1. Create or reuse `.agent-workspaces/issue-<number>/` for the issue you are validating.
2. Launch from that worktree with `cd .agent-workspaces/issue-<number>/godot-world && godot --path .`.
3. If you need the editor UI, use `cd .agent-workspaces/issue-<number>/godot-world && godot --editor --path .`.
4. Avoid validating from repo-root `godot-world` when the actual change only exists in the issue worktree.

- move the in-world player directly inside a simple 2D plaza first
- approach the in-world GM and interact with `E` or left click
- GM画面で相談を送ると、提案されたルールパッチを JSON とメタデータ付きで確認し、承認してから導入できます
- add `時間ルール` from the GM screen when you want the playable 2D/3D world HUD to expose the shared `elapsed_seconds` clock
- press `T` in either the 2D or 3D world to toggle the live rule tree overlay
- apply `3D化` from the GM screen when you want to convert the live world to 3D
- view rules, world state, and admin-heavy inspectors only after entering the GM screen
- continue play in the quarter-view third-person 3D world after the conversion

The old inspector-heavy shell still exists, but it now lives behind the GM interaction flow instead of being the primary scene.

## 2D-to-3D world runtime

The runtime now starts the main world in 2D and treats `snapshot["three_d_preview"]["enabled"]` as the live switch that converts the same world into 3D.

- characters, the GM, and world props are rendered in the starting 2D world and then promoted into simple box-like placeholders in-world after `3D化`
- lighting/floor/camera data become active when the GM applies `3D化`
- `light` and `gravity` rules still demonstrate rule-driven visual changes such as shadows and falling objects
- the same `snapshot["three_d_preview"]` contract can be reused by inspector-side tooling, but it also drives the 3D playable world scene

Expected exploration flow is now scene-first:

1. launch the Godot playable scene
2. walk the player through the 2D world toward the GM
3. talk to the GM and apply `3D化` when you want to convert the current world
4. return to the world and continue in the 3D space without rebooting

If a requested mechanic does not already map to a built-in package, it should still follow the existing safe rule-package/draft workflow rather than bypassing the data-driven runtime model.

### WorldState API

- `submit_player_task(task_text: String) -> Dictionary`
- `review_rule_package_proposal(rule_package: Dictionary) -> Dictionary`
- `clone_rule(rule_id: String) -> Dictionary`
- `create_rule_from_patch(rule_patch: Dictionary) -> Dictionary` — accepts either a runtime rule patch or a reviewed rule package proposal
- `get_world_snapshot() -> Dictionary`
- `get_available_rule_packages() -> Array`
- `create_world_snapshot() -> Dictionary`
- `restore_world_snapshot(snapshot_data: Dictionary) -> Dictionary`
- `save_world_snapshot(file_path: String) -> Dictionary`
- `load_world_snapshot(file_path: String) -> Dictionary`
- `get_available_rule_templates() -> Array`
- `advance_tick(delta_seconds: float) -> void`
- `set_entity_position(entity_id: String, position_patch: Dictionary) -> Dictionary`

`get_world_snapshot()` keeps returning the live inspector/playable payload. Use `create_world_snapshot()` when you need the deterministic save format for persistence, and `restore_world_snapshot()` / `load_world_snapshot()` when you want to rebuild the runtime from that saved payload.

## Snapshot save format

`create_world_snapshot()` returns a JSON-serializable dictionary with this top-level structure:

```json
{
  "snapshot_type": "godot_world_state_snapshot",
  "snapshot_version": 1,
  "runtime": {
    "fixed_step_seconds": 0.25,
    "accumulator_seconds": 0.0,
    "clone_sequence": 0
  },
  "template_catalog": {
    "available_template_ids": ["hunger", "three_d_preview_rule"]
  },
  "world": {
    "world_id": "starter-plaza",
    "world_name": "はじまりの広場",
    "elapsed_seconds": 0.0,
    "tick_index": 0,
    "concepts": ["main_scene_2d_start", "gm_in_world"],
    "preview_3d": {
      "enabled": false,
      "lighting": {
        "enabled": false,
        "shadows_enabled": false,
        "light_rotation_degrees": { "x": -58.0, "y": 36.0, "z": 0.0 },
        "color": "#fff1cf",
        "intensity": 1.4
      },
      "gravity": {
        "enabled": false,
        "floor_y": 0.0,
        "acceleration": 9.8
      },
      "camera": {
        "position": { "x": 6.6, "y": 6.0, "z": -7.4 },
        "look_at": { "x": 0.0, "y": 1.4, "z": 0.4 },
        "fov_degrees": 60.0
      }
    },
    "entities": [{ "id": "origin_entity" }],
    "installed_rules": [{ "id": "rule_hunger", "metadata": {} }],
    "player_task_history": [],
    "event_log": []
  }
}
```

- `runtime` stores the deterministic counters needed to resume ticking without resetting the fixed-step accumulator.
- `template_catalog.available_template_ids` records which built-in templates were available when the save was created; installed rules themselves are restored from the snapshot payload, so package metadata on saved rules survives reload.
- `world.preview_3d` is always serialized with normalized defaults for `enabled`, `lighting`, `gravity`, and `camera`, even when the world is currently running in 2D mode.
- `world.entities` and `world.installed_rules` are saved as stable arrays sorted by id so the JSON stays data-driven and diff-friendly.

## Snapshot limitations

- Snapshot save/load persists the simulation runtime state only. Live scene nodes, current UI focus, and other transient editor/view state are rebuilt by the project after reload.
- `save_world_snapshot(file_path)` needs a writable path. `user://` is recommended for creator-facing saves; `res://` is fine for local development smoke tests but is read-only in exported builds.
- The loader currently accepts `snapshot_version: 1` only. Future format changes should add a new version and an explicit migration path instead of silently guessing.

### Desktop inspector (PoC2)

`scripts/ui/main_desktop.gd` now derives richer presentation directly from `get_world_snapshot()` data.

- Installed rules keep the flat list + raw JSON view and add a dependency tree derived client-side from snapshot metadata.
- If rules expose `resolved_parent_rule_ids`, the tree nests children under their resolved parents.
- If parent links are still unresolved, the tree falls back to `requires_rule_kinds` / `provides_rule_kinds` and calls out unmet required parent kinds.
- The world panel now groups character-style entities vs object-style entities and surfaces common ownership/containment fields such as `owner_id`, `container_id`, `location_id`, and `contained_entity_ids`.

### 3D world payload contract

The runtime exposes `snapshot["three_d_preview"]` as the shared 3D scene payload for both the playable main scene and any secondary inspector renderer path.

- `enabled` — whether 3D preview rendering should be active.
- `renderables` — deterministic box-style entity data with `id`, `name`, `kind`, `is_character`, `is_gm`, `position`, `size`, `color`, plus optional `physics` / `state`.
- `lighting` — preview light settings including `enabled`, `shadows_enabled`, and `light_rotation_degrees`.
- `gravity` — preview gravity settings including `enabled` and `floor_y`; dynamic entities can fall over runtime ticks.
- `camera` — optional camera hint for the preview scene.
