# Godot World PoC

This folder contains the current Godot 4 desktop PoC for the repository.

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

## Runtime overview

- Runtime choice: **Godot 4 desktop**
- Default scene: `scenes/Main.tscn`
- Autoload singleton: `scripts/core/WorldState.gd`
- Runtime model: `scripts/core/SimulationRuntime.gd`

## Running locally

1. Install Godot 4 locally.
2. Open `godot-world/project.godot` in the Godot editor, or run `godot --path godot-world` from the repository root.
3. Launch the default scene.
4. Follow the PoC2 2D flow first.
5. Optionally open the PoC3 3D proof from the GM overlay.
