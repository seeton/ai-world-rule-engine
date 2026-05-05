# AI World Rule Engine

This repository now centers on the Godot-based world/rule engine under `godot-world/`.

## Repository layout

- `godot-world/` — active Godot 4 simulation project
- `godot-world/docs/` — workflow and rule package documentation

Start with [`godot-world/README.md`](./godot-world/README.md) for the project overview and [`CONTRIBUTING.md`](./CONTRIBUTING.md) for the repo workflow.

## GitHub workflow

Default development flow is **issue → branch → PR**.

- Start from a GitHub issue before implementing.
- Use small issue slices so parallel agents can work in separate branches/PRs.
- Keep gameplay, runtime, and rule package work under `godot-world/`.
- See [`CONTRIBUTING.md`](./CONTRIBUTING.md) for branch naming, PR expectations, multi-agent coordination, and rule-package upstream contribution rules.
