# AGENTS

## Required workspace workflow

- Start from a tracked GitHub issue before changing code or docs.
- Create or reuse a repo-local git worktree under `.agent-workspaces/<issue-or-scope>/`.
- Create the issue branch in that worktree with `git worktree add .agent-workspaces/<issue-or-scope> -b <branch-name>` when the worktree does not already exist.
- Reuse the same worktree for follow-up commits on the same issue whenever practical.
- Keep scratch notes, logs, and generated artifacts inside that worktree or other ignored repo-local paths.
- Never create extra clones or checkouts under `/Users/seeton`, `~`, or any other home-directory location.

## Repo scope reminders

- `godot-world/` is the active Godot 4 project.
- The repo root Node app is an older PoC and should remain unchanged unless the issue explicitly targets it.
- Open a PR linked to the issue after validation.
