# AI World Rule Engine

This repository now centers on the Godot-based world/rule engine under `godot-world/`.

## Repository layout

- `godot-world/` — active Godot 4 simulation project
- `godot-world/docs/` — workflow and rule package documentation

Start with [`godot-world/README.md`](./godot-world/README.md) for the project overview and [`CONTRIBUTING.md`](./CONTRIBUTING.md) for the repo workflow.

## GitHub workflow

Default development flow is **issue → repo-local worktree → branch → PR**.

- Start from a GitHub issue before implementing.
- Create or reuse a repo-local git worktree under `.agent-workspaces/<issue-or-scope>/`.
- Create the issue branch with `git worktree add .agent-workspaces/<issue-or-scope> -b <branch-name>` when needed, then reuse that worktree for follow-up commits.
- Keep scratch notes, logs, and generated artifacts inside that worktree or other ignored repo-local paths.
- Use small issue slices so parallel agents can work in separate branches/PRs.
- Keep gameplay, runtime, and rule package work under `godot-world/`.
- Do not create extra clones or checkouts in `/Users/seeton`, `~`, or other home-directory paths.
- See [`CONTRIBUTING.md`](./CONTRIBUTING.md) for worktree setup, branch naming, PR expectations, multi-agent coordination, and rule-package upstream contribution rules.
