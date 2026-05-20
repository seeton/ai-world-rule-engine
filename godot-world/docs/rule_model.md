# Rule model

This document describes the gameplay-facing rule model that the runtime and tools should share.

## Parent and child rules

A rule can be a root rule or a child rule.

- Rules form a directed acyclic prerequisite graph (DAG) rather than a strict tree.
- A root rule has no parent prerequisites.
- A child rule can depend on one or more parent rules.
- A child rule can only apply after all of its parent rules are already applied.
- Required parent prerequisites cannot be skipped in order to apply a deeper child rule.

In practice, progression must move through the prerequisite graph in order: rules without prerequisites can apply first, and each dependent child rule unlocks only after every required parent is already active. A descendant may therefore sit behind multiple parent chains while still remaining a single rule node in the shared model.

A descendant can therefore be described in equivalent ways:

- as a rule that sits behind one or more prerequisite parent rules
- as a child rule that may be shared by multiple parent branches in the same graph

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
2. which prerequisite parent rules must already be active, including every required parent when there is more than one
3. whether its `Representation` is visible, internal-only, or conditionally visible

This keeps runtime behavior, tools, and future UI work aligned around the same rule invariants.

## See also

- [`rule_composition_invariants.md`](rule_composition_invariants.md) — world-order composition contract (DAG shape, implemented package-dependency rejection, future capability-cycle rejection, deterministic snapshot `rule_tree` view, conflict semantics on stat / relation / event binding / capability, 2D / 3D parity, and the 18-rule base taxonomy). New world-order rules must follow that contract on top of the rule model defined here.
