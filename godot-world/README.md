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
- Template catalog: `scripts/core/RuleTemplates.gd`
- Optional bootstrap scene: `scenes/Bootstrap.tscn`

The core foundation starts from a null world with a mutable origin entity. Rules are additive data patches: AI proposes them, and the deterministic fixed-step runtime executes them without arbitrary code execution.

## Playable main scene (PoC3)

The current Godot entry point in `scenes/Main.tscn` starts in a playable 2D world and switches to the playable 3D world after the GM applies `3D化`.

### Launching from an issue worktree

Use the worktree-specific launcher instead of opening the repo-root project directly.

1. Create or reuse `.agent-workspaces/issue-<number>/` for the issue you are validating.
2. Make sure that worktree is the claimed owner for the issue with `bash scripts/agent_guard.sh claim-issue <issue-number> .agent-workspaces/issue-<number>`.
3. Launch from a repository checkout with `bash scripts/launch_godot.sh <issue-number>`.

Useful variants:

- `bash scripts/launch_godot.sh <issue-number> --dry-run`
- `bash scripts/launch_godot.sh <issue-number> -- --editor`

The launcher resolves `godot-world` inside `.agent-workspaces/issue-<number>/`, rejects repo-root `godot-world`, blocks project paths that escape the selected worktree, and only permits detached-HEAD launches when `--allow-detached-head` is passed intentionally. Use `bash scripts/agent_guard.sh status` if you need to confirm the current issue/worktree ownership before reusing an existing workspace.

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
- `create_rule_from_patch(rule_patch: Dictionary) -> Dictionary`
- `get_world_snapshot() -> Dictionary`
- `get_available_rule_packages() -> Array`
- `get_available_rule_templates() -> Array`
- `advance_tick(delta_seconds: float) -> void`
- `set_entity_position(entity_id: String, position_patch: Dictionary) -> Dictionary`

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
