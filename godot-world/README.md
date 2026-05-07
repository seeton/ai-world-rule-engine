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

### WorldState API

- `submit_player_task(task_text: String) -> Dictionary`
- `clone_rule(rule_id: String) -> Dictionary`
- `create_rule_from_patch(rule_patch: Dictionary) -> Dictionary`
- `get_world_snapshot() -> Dictionary`
- `get_available_rule_templates() -> Array`
- `advance_tick(delta_seconds: float) -> void`
