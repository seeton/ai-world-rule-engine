# AI World Rule Engine

This repository hosts a **Godot 4 world-rule engine** built around safe, data-driven rule packages.

The active project lives in `godot-world/` and focuses on simulation/runtime behavior, reusable rule packages, and the repository workflow needed to evolve both safely.

## Repository layout

- `godot-world/` — Godot 4 project, simulation runtime, scenes, and rule-package tooling.
- `godot-world/rules/packages/` — reusable rule packages for mechanics and content.
- `godot-world/rules/schema/` — schema contract for package validation and review.
- `.github/` — issue and PR templates for the issue-driven multi-agent workflow.
- `CONTRIBUTING.md` — branch naming, PR expectations, and collaboration rules.

## Getting started

1. Install **Godot 4**.
2. Open the `godot-world/` project in the Godot editor.
3. Review `godot-world/README.md` for project internals.
4. Review `godot-world/docs/rule_packages.md` before changing package data or package workflows.

## What this repo is for

- building a deterministic Godot world simulation
- extending mechanics through reviewable rule packages
- keeping package changes schema-safe and provenance-aware
- coordinating work through issues, branches, and pull requests

## Default GitHub workflow

Default development flow is **issue → branch → PR**.

- Start from a tracked GitHub issue.
- Keep changes scoped to the issue acceptance criteria.
- Use small issue slices so parallel agents can work in separate branches and PRs.
- Preserve clear ownership: one issue, one branch, one PR per implementation agent.
- Use [`CONTRIBUTING.md`](./CONTRIBUTING.md) for branch naming, PR expectations, and multi-agent coordination details.

## Rule package workflow

Rule packages are designed to be **cloneable, forkable, and reviewable**.

- Clone an existing package when a mechanic already fits.
- Fork a package when you need a variant and keep provenance metadata intact.
- Create a new package only when no existing package is a good base.
- Keep package data declarative; do not introduce arbitrary code execution into package content.

See `godot-world/docs/rule_packages.md` for package format, provenance metadata, and upstream contribution notes.
