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

### WorldState API

- `submit_player_task(task_text: String) -> Dictionary`
- `clone_rule(rule_id: String) -> Dictionary`
- `create_rule_from_patch(rule_patch: Dictionary) -> Dictionary`
- `get_world_snapshot() -> Dictionary`
- `get_available_rule_templates() -> Array`
- `advance_tick(delta_seconds: float) -> void`
