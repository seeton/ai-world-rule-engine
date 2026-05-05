# Godot World PoC

This folder contains the current Godot 4 desktop PoC for the repository.

## What the PoC does

The default scene starts a plain white 2D world with exactly two actors:

- one player character
- one game master

The player can move around the scene and can only talk to the game master. Opening the game master screen uses the Japanese PoC flow by default, and the player can always return to the 2D world. When the user asks the game master to create the time rule, the game master deterministically installs the predefined time rule from `rules/packages/time.rule.json`. After returning to the scene, a clock appears in the top-right and advances in fixed day / hour / minute / second units.

The PoC intentionally does **not** define morning, noon, aging, or other time-derived world concepts.

## Main folders

- `scenes/` — Godot scenes, including the default playable PoC scene
- `scripts/core/` — world state and deterministic simulation runtime
- `scripts/game/` — 2D world scene controller and character scripts
- `scripts/ui/` — game master interaction UI
- `rules/packages/` — predefined rule data, including the time rule
- `docs/` — supporting workflow notes

## Runtime overview

- Runtime choice: **Godot 4 desktop**
- Default scene: `scenes/Main.tscn`
- Autoload singleton: `scripts/core/WorldState.gd`
- Runtime model: `scripts/core/SimulationRuntime.gd`

### WorldState API

- `talk_to_game_master(message: String) -> Dictionary`
- `create_rule_from_patch(rule_patch: Dictionary) -> Dictionary`
- `get_world_snapshot() -> Dictionary`
- `advance_tick(delta_seconds: float) -> void`

`get_world_snapshot()` exposes the data needed by the PoC UI, including:

- `entities`
- `conversation_log`
- `clock`

## Running locally

1. Install Godot 4 locally.
2. Open `godot-world/project.godot` in the Godot editor, or run `godot --path godot-world` from the repository root.
3. Launch the default scene.
4. Move the player in the white 2D scene and click the game master when you are close enough.
5. In the Japanese game master screen, send a message such as `時間のルールを作成しろ`.
6. Return to the 2D scene and confirm that the clock appears in the top-right and starts advancing.
