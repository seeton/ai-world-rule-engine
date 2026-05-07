# Codex rule proposal contract

PoC4 uses Codex to draft player-requested rule ideas, but Codex output is not trusted as a rule package or GitHub issue directly.

Every generated response must first be normalized into a `codex_rule_proposal_v1` proposal and pass the proposal validation gate. Only validated proposal data may be shown for player review or converted into a GitHub issue body.

## Contract file

The checked-in proposal schema lives at:

- `godot-world/rules/schema/rule_proposal.schema.json`

This schema defines the data that sits between a raw Codex response and the later issue / branch / PR workflow.

## Required proposal data

A proposal must include:

- `schema_version`: must be `codex_rule_proposal_v1`
- `proposal_title`: human-readable title for review
- `player_request_summary`: summary of the player request that produced the proposal
- `package_id`: proposed package id using the rule package id format
- `package_schema_version`: must be `rule_package_v1`
- `patch`: declarative `rule_patch_v1` operation preview
- `touched_surfaces`: declared stats, rules, event bindings, and relations touched by the proposal
- `risk_notes`: review notes for humans
- `validation`: schema / semantic / safety findings
- `review_status`: proposal review state
- `issue`: title and body sections used when converting the proposal into a GitHub issue

## Validation gate

A proposal may advance only after passing these gates:

1. **Schema validation**: the proposal matches `rule_proposal.schema.json`.
2. **Patch operation validation**: `patch.operations[*].op` uses the same allowed operation set as `rule_package.schema.json`.
3. **Semantic validation**: the proposal declares which runtime surfaces it expects to touch.
4. **Safety validation**: the proposal does not ask the project to run scripts, expose secrets, bypass review, or post externally outside the approved issue flow.

Validation produces one of these statuses:

- `valid`: structurally valid and ready for normal review
- `repairable`: missing or weak data can be repaired before review
- `needs_human_review`: structurally acceptable but requires design judgment
- `rejected`: not safe or not usable as a rule proposal

## Review status

The `review_status` field is intentionally conservative:

- `needs_design_review`: the normal state for Codex-generated proposals
- `repair_required`: the proposal needs correction before it can be reviewed
- `rejected`: the proposal should not advance

Codex-generated proposals should not mark themselves as approved. Approval belongs to the human review / implementation workflow, not the LLM response.

## Issue conversion

GitHub issue creation must use the structured `issue` block from the proposal. The issue should preserve at least:

- title
- player request summary
- package id
- operation count and operation types
- touched stats / rules / event bindings / relations
- validation status and findings
- review status
- suggested PR target, when present

The issue must make clear that the proposal is for human review before implementation.

## Safety boundary

Raw Codex text must not be treated as executable instructions.

Reject or hold for review any response that attempts to:

- include arbitrary script execution
- request local files or secrets
- change the target repository outside the configured flow
- create a GitHub issue before explicit player consent
- bypass validation, review, branch, or PR steps
- introduce schema fields that are not part of the proposal contract

This keeps the PoC4 flow data-driven and reviewable while still allowing Codex to help draft rule ideas.

## Related issues

- Parent: #60
- Contract implementation: #85
- Credential policy: #63
- Dry-run / sandbox policy: #64
- UI controller separation: #65
