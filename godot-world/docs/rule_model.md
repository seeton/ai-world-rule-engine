# Rule model

This document describes the gameplay-facing rule model that the runtime and tools should share.

## Parent and child rules

A rule can be a root rule or a child rule.

- Rules form a strict tree.
- A child rule can only apply after its parent side of the tree is already applied.
- Parent parts of the tree cannot be skipped in order to apply a deeper child rule.

In practice, this means progression must move through the tree in order: root first, then its children, then deeper descendants.

A descendant can be described in two equivalent ways:

- as a rule nested inside a child rule
- as a child rule's child rule

## Representation contract

Every rule owns a `Representation`.

- Some rules have a visible `Representation` that the player can see in the world.
- Some rules have an internal-only `Representation` that does not render visible output.

The important invariant is that the `Representation` always exists, even when it is not meant to be shown on screen.

Systems should therefore treat visibility and existence as separate concepts:

| Concept | Meaning |
| --- | --- |
| Rule exists | The rule is present in the simulation model. |
| Representation exists | The rule has a corresponding `Representation` record or object. This is always true for active rules. |
| Representation is visible | The `Representation` is currently rendered or otherwise exposed to the player. This may be true or false depending on the rule. |

## Examples

| Rule | Representation exists | Representation visible | Notes |
| --- | --- | --- | --- |
| Time rule | Yes | Yes | Time has a display object or presentation that players can observe. |
| Gravity rule | Yes | No | Gravity still needs an internal `Representation` even when nothing is drawn for it directly. |

## Documentation guidance

When a new rule is added or an existing rule is changed, document:

1. whether it is a root rule or a child rule
2. where it sits in the parent/child tree and which parent chain must already be active
3. whether its `Representation` is visible, internal-only, or conditionally visible

This keeps runtime behavior, tools, and future UI work aligned around the same rule invariants.
