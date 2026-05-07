## Summary

- Linked issue:
- Scope:
- Why this change:

## Workflow

- [ ] Work started from a tracked GitHub issue
- [ ] Changes were implemented on a dedicated branch
- [ ] This PR is scoped to the issue acceptance criteria
- [ ] Any follow-up work has been split into new issues instead of expanding scope
- [ ] Copilot automatic review completed, or this PR explicitly notes that no automatic review was configured/available
- [ ] Any overlapping open PRs were classified (`merge-ready` / `needs-fix` / `superseded` / `split-required` / `close`) before merge or close decisions
- [ ] If this existing PR received follow-up changes and needs another review pass, I added a PR comment that says `@copilot レビューをお願いします` (not for the initial creation of a new PR)
- [ ] This PR does not rely on helper scripts or workflow tooling that are not tracked in this branch

## Multi-agent execution notes

| Agent / owner | Scope | Outcome |
| --- | --- | --- |
| Agent A |  |  |
| Agent B |  |  |
| Agent C |  |  |

## Godot / rule package impact

- [ ] No Godot gameplay behavior changed
- [ ] Godot runtime or scene behavior changed
- [ ] Rule package data changed under `godot-world/rules/packages/`
- [ ] Rule package schema or workflow docs changed
- [ ] Root docs or workflow metadata changed

If rule packages changed, summarize:

- Package ID(s):
- `forked_from` / provenance:
- `suggested_pr_target`:

## Acceptance criteria check

- [ ] Issue acceptance criteria are satisfied
- [ ] Validation expectations from the issue are satisfied
- [ ] Docs/config were updated where the workflow changed

## PR overlap / replacement notes

- Related open PRs:
- Source-of-truth PR for this area:
- If this PR closes, replaces, or supersedes another PR, explain why:

## Validation

List exactly what you ran or verified.

### Automated

- [ ] Existing repo checks run
- [ ] `git diff --check` run
- [ ] Godot headless startup or equivalent launch check run when `godot-world/` changed
- [ ] Not applicable

### Manual / reviewer checks

- [ ] Godot behavior verified manually
- [ ] Rule package reviewed against `godot-world/rules/schema/rule_package.schema.json`
- [ ] Clone/fork/PR metadata reviewed for correctness
- [ ] Screenshots, recordings, or logs attached when helpful

### Evidence

```text
Paste concise command output, reproduction notes, classification rationale for overlapping PRs, or review evidence here.
```

## Risks and rollback

- Risk areas:
- Rollback plan:
