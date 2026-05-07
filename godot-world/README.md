# Godot World Rule Packages

This folder contains a data-driven rule package workflow for a Godot 4 simulation game.

## Default flow: PoC2 (2D playable, Japanese-first)

The default scene starts in a **2D playable world**.

1. Move with the arrow keys.
2. Approach the **ゲームマスター** and click or press `E`.
3. In the Japanese GM overlay, progress through:
   - `物体基礎を有効化`
   - `所有関係を有効化`
   - `親子ツリーを有効化`
4. Return to the world and click visible objects to inspect their Japanese state.

PoC2 is considered successful when the player can, in the 2D flow, inspect:

- Object Rule
- Ownership Rule
- parent-child rule tree
- object ownership / placement state

The time rule remains available as a supporting proof, but it is no longer the only guided path.

## Secondary flow: PoC3 (partial 3D proof)

The GM overlay also exposes **PoC3 3D途中証明**.

- This path is **secondary**.
- It exists to keep the 3D proof available.
- The primary success path remains the 2D PoC2 flow.

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

## Running locally

1. Install Godot 4 locally.
2. Open `godot-world/project.godot` in the Godot editor, or run `godot --path godot-world` from the repository root.
3. Launch the default scene.
4. Follow the PoC2 2D flow first.
5. Optionally open the PoC3 3D proof from the GM overlay.
