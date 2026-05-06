# Godot World PoC

This folder contains the current Godot 4 PoC for the repository.

## What is here

The project keeps two complementary Godot entry points on top of the same `WorldState` autoload:

- `scenes/Main.tscn` is the default playable 2D scene with one player and one game master
- `scenes/DesktopShell.tscn` is the desktop shell for rule-package review, installation, and snapshot inspection

The 2D PoC is the shortest way to verify the current vertical slice: move in the white scene, talk to the game master, ask for the time rule, then return to the world and confirm the clock appears in the top-right.

The desktop shell remains available for package-centric workflows: submit tasks, inspect package proposals, review and install rule packages, clone installed rules, inspect dependency trees, save/load snapshots, and preview optional 3D metadata.

## Main folders

- `scenes/` - Godot scenes for the 2D PoC, desktop shell, and bootstrap path
- `scripts/core/` - `WorldState` and deterministic runtime logic
- `scripts/game/` - 2D scene controller and in-world interaction scripts
- `scripts/ui/` - desktop shell, game master dialog, and preview UI
- `scripts/integration/` - rule-package repository, task resolution, and runtime patch compilation
- `rules/packages/` - predefined rule packages
- `docs/` - supporting workflow notes

## Runtime overview

- Runtime choice: **Godot 4 desktop**
- Default scene: `scenes/Main.tscn`
- Desktop shell scene: `scenes/DesktopShell.tscn`
- Optional bootstrap scene: `scenes/Bootstrap.tscn`
- Autoload singleton: `scripts/core/WorldState.gd`
- Runtime model: `scripts/core/SimulationRuntime.gd`
- Rule package catalog: `rules/packages/*.rule.json`

## WorldState API

- `submit_player_task(task_text: String) -> Dictionary`
- `talk_to_game_master(message: String) -> Dictionary`
- `create_rule_from_patch(rule_patch: Dictionary) -> Dictionary`
- `clone_rule(rule_id: String) -> Dictionary`
- `get_world_snapshot() -> Dictionary`
- `save_world_snapshot(file_path: String = "user://world_snapshot.json") -> Dictionary`
- `load_world_snapshot(file_path: String = "user://world_snapshot.json") -> Dictionary`
- `restore_world_snapshot(snapshot: Dictionary) -> Dictionary`
- `get_available_rule_packages() -> Array`
- `get_available_rule_templates() -> Array`
- `advance_tick(delta_seconds: float) -> void`

`get_world_snapshot()` is the exported snapshot shape shared by both the 2D PoC and the desktop shell. Persisted snapshots are versioned by `SimulationRuntime.SNAPSHOT_FORMAT_VERSION`; `save_world_snapshot()` writes the exported shape, and `load_world_snapshot()` / `restore_world_snapshot()` rebuild runtime state from the canonical fields.

## Running locally

1. Install Godot 4.2 locally.
2. Open `godot-world/project.godot` in the Godot editor, or run `godot --path godot-world` from the repository root.
3. Launch the default scene for the 2D PoC, or open `res://scenes/DesktopShell.tscn` manually if you want the package inspector flow instead.

### 2D PoC flow

1. Move the player in the white 2D scene.
2. Approach the game master and click it, or press `E` when in range.
3. In the Japanese-first game master screen, send a message such as `時間のルールを作成しろ`.
4. Return to the world and confirm that the clock appears in the top-right and advances.

### Desktop shell flow

1. Open `res://scenes/DesktopShell.tscn`.
2. Submit a task such as `add hunger` and inspect the generated package proposal metadata.
3. Install an approved built-in package, or review/edit/approve a draft package before installing it.
4. Inspect installed rules, dependency relationships, world/object state, snapshot output, and optional 3D preview data.

## Repository validation

Run the repository validator before opening or updating a PR that changes rule packages, the package schema, scenes, `project.godot`, or GDScript files with `res://` references.

- From `godot-world/`, run `./scripts/validate_repo.sh`
- From the repo root or another checkout, run `python3 godot-world/scripts/validate_repo.py --root godot-world`

The validator checks that:

- every `rules/packages/*.rule.json` file is valid JSON and matches `rules/schema/rule_package.schema.json`
- `package_id` values stay unique and package filenames match their `package_id`
- static `res://` references in scenes, scripts, and `project.godot` point to files that exist
- `.tscn` files only use `ExtResource(...)` ids declared in the same scene

## Notes and current limitations

- Godot is not installed in this automation environment, so runtime verification still requires a local/manual pass.
- `scripts/ui/main_desktop.gd` intentionally falls back to a preview snapshot when `/root/WorldState` is unavailable; manual validation should confirm the status line says `WorldState autoload`.
- `scripts/integration/runtime_rule_patch_compiler.gd` currently applies `upsert_stat` and `upsert_rule` entries with `rule_type = "tick_delta"` directly; other package operations remain as deferred metadata until runtime support expands.

### Desktop shell and preview notes

- The desktop shell builds its dependency tree from installed rule metadata such as `resolved_parent_rule_ids`, `requires_rule_kinds`, and `provides_rule_kinds`.
- The world/object inspector groups character-style entities vs object-style entities and surfaces ownership/containment fields when present.
- The optional 3D preview payload lives under `snapshot["three_d_preview"]` and may include `renderables`, `lighting`, `gravity`, and `camera` hints.
