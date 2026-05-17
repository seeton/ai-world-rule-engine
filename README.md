# AI World Rule Engine

**AI World Rule Engine** is an experimental Godot 4 project for building a playable world where rules and world behavior are described as data, then applied to a deterministic simulation runtime.

The active product in this repository is the Godot project under [`godot-world/`](./godot-world/). If you are visiting this repo on GitHub for the first time, start there.

## What this repository is

This repo is currently focused on a small game/simulation prototype with a rule-package workflow:

- a **playable Godot world** that starts in 2D and can shift into a simple 3D view
- a **data-driven rule system** for stats, rules, events, relations, and world patches
- a **safe authoring model** where mechanics are represented as structured package data instead of arbitrary script execution

## Current project facts

The current state of the repository is:

| Area | What it contains |
| --- | --- |
| [`godot-world/`](./godot-world/) | Active Godot 4 project, scenes, runtime scripts, rule packages, and project-specific docs |
| [`godot-world/docs/`](./godot-world/docs/) | Deeper documentation for rule packages, workflows, and integration details |
| [`scripts/`](./scripts/) | Repository workflow helpers for worktrees, coordination guards, and Copilot/Godot launch scripts |
| [`CONTRIBUTING.md`](./CONTRIBUTING.md) | Contributor workflow, branch naming, PR expectations, and multi-agent coordination rules |
| [`test/`](./test/) | Repository-level automated checks for contract and workflow behavior |

## Where to start

- **Project overview:** [`godot-world/README.md`](./godot-world/README.md)
- **Contributor workflow:** [`CONTRIBUTING.md`](./CONTRIBUTING.md)
- **Rule package format/details:** [`godot-world/docs/`](./godot-world/docs/)

## Project direction

The repository is currently moving toward:

- a larger library of reusable rule packages
- a clearer GM/player workflow for applying and testing mechanics in-world
- better authoring and review loops for AI-proposed rule changes
- keeping the runtime data-driven and safe, without arbitrary code execution in package data

## GitHub workflow

This repository uses **issue -> branch -> PR** as the default development flow.

- Start from a GitHub issue before implementing.
- Use small issue slices so parallel agents can work in separate branches/PRs.
- Keep changes scoped to one issue per branch/worktree.
- Open a PR for review instead of merging directly to `main`.
- If a PR relies on Copilot automatic review, wait for that review to complete before merging; otherwise note explicitly that no automatic review was available.
- Keep gameplay, runtime, and rule package work under `godot-world/`.
- See [`CONTRIBUTING.md`](./CONTRIBUTING.md) for detailed branch naming, PR expectations, multi-agent coordination, and rule-package upstream contribution rules.

## Copilot CLI defaults

Use `bash scripts/launch_copilot.sh` from the issue worktree you are actively editing when you want the repository defaults for Copilot CLI:

- `--model gpt-5.4`
- `--effort high`
- `--allow-all`

The launcher prepends those defaults and then forwards any extra Copilot arguments, so later arguments can still override them when needed.

## Repo-root main checkout

Keep the repo-root `main` checkout as a sync-only baseline. Do implementation work in `.agent-workspaces/issue-<number>/`, inspect the repo-root state with `bash scripts/worktree.sh root-status`, inspect worktree backlog with `bash scripts/worktree.sh status --stale-days 14`, and fast-forward repo root with `bash scripts/worktree.sh sync-root` when tracked files are clean.
