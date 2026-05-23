# World-order rule composition invariants

This document closes issue #86. It defines the composition contract that every world-order rule package (and the surfaces that observe them) must follow, so that #62 and subsequent peaceful world-order work can be implemented against a stable invariant set.

The contract is intentionally a **superset** of the existing rule model. It does not roll back any of the following already-settled decisions:

- rules form a directed acyclic prerequisite graph (DAG), not a strict tree
- a child rule may depend on more than one parent rule
- a child rule may only apply after every required parent is already active
- required parent prerequisites cannot be skipped
- every rule owns a `Representation` (visible, internal-only, or conditionally visible)
- the default package is a removable / disableable / replaceable initial rule set, not an immutable engine invariant
- peaceful world-order rules depend on `world.*` **capability kinds**, not on default-package rule ids
- package dependency cycles are invalid; capability-kind cycles are invalid as a target invariant but are not fully rejected by the current runtime yet

For the prerequisite-graph and `Representation` basics see [`rule_model.md`](rule_model.md). For the package format and the default-package vs. peaceful-world-order split see [`rule_packages.md`](rule_packages.md). This document specializes both for the world-order layer and pins the remaining edge-cases that #86 asked to close.

## 1. Terminology

The following terms are used consistently across docs, tools, snapshots, and rule packages. They are not synonyms-by-accident; each one has a single meaning in the model.

| Term | Meaning |
| --- | --- |
| **rule** | A single declarative unit identified by `rule_id`. Always owns a `Representation`. |
| **root rule** | A rule with no required prerequisites. It can apply as soon as it is installed and enabled. |
| **child rule** | A rule that has at least one required prerequisite. Equivalent to *dependent rule*. |
| **parent rule** | A rule that satisfies one or more of another rule's prerequisites. Equivalent to *prerequisite rule*. |
| **prerequisite** | A condition that must hold before a rule can apply. In this model a prerequisite is always expressed as a required **capability kind**. |
| **dependency edge** | A directed edge from a parent rule to a child rule in the prerequisite DAG. The edge exists because the child requires a capability kind that the parent provides. |
| **capability kind** | An abstract name (string) such as `world.space` or `world-order.time`. Producers advertise it via `provides_rule_kinds`; consumers require it via `requires_rule_kinds`. Capability kinds are the only allowed coupling between packages. |
| **consumer** | A rule that lists a capability kind in `requires_rule_kinds`. |
| **provider** | A rule that lists a capability kind in `provides_rule_kinds`. |
| **resolved parent rule** | A specific installed rule chosen by the runtime to satisfy a required capability kind. Surfaced as `resolved_parent_rule_ids` in the snapshot. |

A "dependency" in this document always means a capability-kind dependency unless the surrounding text says otherwise. Dependencies between concrete rule ids are not part of the world-order contract; they only ever exist as a runtime resolution outcome (`resolved_parent_rule_ids`).

## 2. Graph shape

The world-order rule graph is a directed acyclic prerequisite graph (DAG) keyed by capability kind, projected onto rule ids at runtime.

- **Single node per rule.** Each installed rule appears exactly once in `rule_tree.nodes_by_rule_id`, regardless of how many parents it has.
- **Multiple parents allowed.** A child rule may have any non-empty subset of capability kinds in `requires_rule_kinds`. Every required kind must be satisfied by at least one provider before the child can apply.
- **Multiple providers per capability kind allowed.** A capability kind may be advertised by more than one rule. This represents alternative providers (e.g. the 2D space rule and the 3D space rule both providing `world.space`), not conflict.
- **Root rules have no required kinds.** A rule with an empty `requires_rule_kinds` is a root rule. Roots are surfaced as `rule_tree.root_rule_ids`.
- **Shared descendants.** A descendant rule may sit behind several parent chains in the DAG. It remains a single node; the chains share that node rather than duplicating it.

Existing examples already exercise multi-parent dependencies. For instance `world_order.time` requires both `world-order.base` and `world.base-time`; `world_order.objects` requires `world-order.base`, `world.existence`, and `world.space`. These are the shape #62 will continue to extend.

## 3. Cycle rejection

Cycles are invalid and must be rejected, regardless of whether they appear at the package layer or the rule layer.

A cycle is any closed loop in the directed graph formed by `requires_rule_kinds` -> provider(s) -> that provider's `requires_rule_kinds` -> back to a previously visited rule (or the starting capability kind).

Cycle handling is split between behavior that exists today and behavior that future world-order work must add before relying on it:

1. **Package install, implemented today.** `WorldState` rejects cyclic `package_dependencies` with a `Rule package dependency cycle detected` error. Unknown `package_dependencies` are rejected before install.
2. **Rule resolution, target invariant.** A capability-kind self-loop (the same kind in `requires_rule_kinds` and `provides_rule_kinds`) and a capability-kind cycle between rules are invalid. The current resolver checks that each required kind has at least one active provider, but it does not yet detect all capability-kind cycles. A future runtime change must reject those cycles before any package relies on this guarantee.
3. **Snapshot rendering, implemented today.** `_build_rule_tree_node` uses an `ancestry` guard so that a buggy DAG which slipped past validation cannot infinite-loop the renderer. The guard truncates one branch and is **not** a substitute for rule-resolution cycle rejection.

Rejecting a package cycle is a hard error today. Rejecting capability-kind cycles is a required follow-up invariant: once implemented, the offending package or rule must not become applied and the error message must name the cycle in dependency order so the author can fix it.

## 4. Ordering

Snapshot rule-tree ordering is deterministic today. Rule application order is a future runtime invariant.

The implemented snapshot order is:

1. `rule_tree.root_rule_ids` sorted ascending by `rule_id`
2. every `node.child_rule_ids` sorted ascending by `rule_id`
3. `nodes_by_rule_id` keyed by one canonical node per installed rule

This matches what `_build_rule_tree()` already does for rendering and inspection. Surfaces that emit the snapshot rule tree (snapshot dumps, CLI output, GM console) must preserve this order verbatim.

Future runtime work that makes effect application dependency-aware must use topological order: every active parent rule is considered before any active child rule that depends on it, with deterministic tie-breaks for rules at the same rank. The current tick loop still applies rule effects by sorted `rule_id`, so this PR does not claim topological effect application is implemented.

## 5. Conflict semantics

Two rules **conflict** when they target the same simulation surface with effects that cannot be combined deterministically. The world-order layer recognises four conflict surfaces, each with explicit rules.

| Surface | Detected conflict | Example |
| --- | --- | --- |
| **Stat** | Two rules declare `upsert_stat` for the same stat with disagreeing definitions (different default, bounds, type), or two rules emit `set` operations on the same stat in the same tick with different values. | Rule A says `hunger.default = 0`, rule B says `hunger.default = 5`. |
| **Relation** | Two rules write to the same relation slot (`owner_of`, `parent_of`, etc.) for the same `(subject, object)` pair in the same tick with different targets. | Rule A sets `owner_of(coin) = alice`, rule B sets `owner_of(coin) = bob` in the same tick. |
| **Event binding** | Two rules bind to the same event with effects that mutate the same stat/relation in incompatible ways (one `set`, one `add` on the same field; or two `set` operations with different values). | Two rules listening to `on_eat` both set the same `hunger` value. |
| **Capability** | A rule declares the same capability kind in both `requires_rule_kinds` and `provides_rule_kinds`, or two rules form a cycle through capability kinds (see §3). Note: **multiple providers of the same capability kind are not a conflict** — they are alternative providers. |

These are contract definitions for #62 and later work. The current runtime does not yet run full stat / relation / event-binding conflict detection and does not emit `dependency_status = "conflicted"`. Until that follow-up lands, package authors must avoid the conflicting shapes above manually and tests must not assume automatic conflict blocking.

When conflict detection is implemented, a conflict must be reported at the latest at package install or rule registration. The runtime should:

- block the conflicting rule (its `dependency_status` becomes `conflicted` and `blocked = true`)
- record the conflict in the audit / event log with both rule ids and the surface
- never silently pick one rule over another

Where a future package legitimately wants to override an existing rule, it must do so explicitly (via a declared `replaces` link or by disabling the displaced rule), not by quietly emitting a conflicting effect.

### 5.1 Non-conflicting composition

Two rules **do not conflict** if any of the following hold:

- They touch different stats, different relation slots, different event keys, or different capability kinds.
- They both emit only **additive** (commutative, associative) operations on the same stat or counter — e.g. both `add 1` to `hunger`. The combined effect is deterministic regardless of application order.
- They both bind to the same event but write to disjoint output fields.
- They both advertise the same capability kind. The current runtime records every matching provider in `resolved_parent_rule_ids` and every active matching provider in `active_parent_rule_ids`; providers do not block or deactivate each other merely because they share a capability kind.

This is the criterion #62 will use when stacking the world-order base set: each rule in §8 is designed so that its effects on shared surfaces are either disjoint or additive.

## 6. Snapshot `rule_tree` vs runtime DAG

The runtime stores a DAG; the snapshot emits both a canonical DAG view and a tree-friendly rendering. Consumers must not assume the rendering is the full picture.

The snapshot's `rule_tree` always carries three fields:

| Field | Shape | Use |
| --- | --- | --- |
| `root_rule_ids` | `Array<rule_id>`, sorted | The rules with no required prerequisites. Stable ordering anchor. |
| `nodes_by_rule_id` | `Dictionary<rule_id, node>` | **Canonical DAG view.** Each rule appears exactly once. Each node lists `resolved_parent_rule_ids` and `child_rule_ids`, both sorted. This is the source of truth for any consumer that cares about graph shape. |
| `roots` | `Array<nested node>` | Tree-friendly rendering produced by descending from each root. A rule with N parents is visited from each parent path; the same `rule_id` will appear multiple times in this nested form. |

The two views are intentionally redundant:

- UIs that draw a tree (CLI overlay, GM tree view) can walk `roots` and accept the duplication.
- Anything that reasons about graph shape (validators, exporters, automation, `#62` capability-kind checks) must read `nodes_by_rule_id` so that shared descendants are not double-counted.

Consumers must never infer that the world-order rule graph is a strict tree from the presence of `roots` alone. The presence of multiple `resolved_parent_rule_ids` on a single node is the explicit signal that the underlying graph is a DAG.

## 7. Representation visibility in world-order

[`rule_model.md`](rule_model.md) defines the three visibility states (visible, internal-only, conditionally visible) and the invariant that a `Representation` always exists. World-order rules follow the same contract; the table below pins the expected visibility for the base set.

| Rule | Default visibility | Notes |
| --- | --- | --- |
| existence | internal-only | The fact that an entity exists is implied by other visible rules; no standalone visible widget. |
| time | visible | Players can read clock / day. |
| space | conditionally visible | 2D/3D runtimes expose position; CLI exposes proximity through `InspectWorld`. |
| representation | internal-only | The representation rule describes the contract itself; it is not separately rendered. |
| state | internal-only | Generic state container; surfaced through rules that consume it. |
| object | conditionally visible | Objects with a visible representation render; abstract objects may not. |
| body | conditionally visible | Body presence is usually rendered; some agents may run headless. |
| movement | conditionally visible | Visible when a body or object actually moves. |
| container-possession | conditionally visible | Inventories may be visible (UI) or internal-only (off-screen NPCs). |
| relationship | internal-only | Relationship facts are queried, not drawn. |
| ownership | conditionally visible | Owner badges / coloured outlines optional. |
| action | conditionally visible | Action log may be visible (CLI / overlay) or internal. |
| resource | conditionally visible | Resource bars visible when bound to a UI; otherwise internal. |
| money | visible | Money is player-facing by default. |
| food | conditionally visible | Food objects render; abstract food stays internal. |
| meal | conditionally visible | Meal events may surface in the action log. |
| hunger | conditionally visible | Hunger gauge visible when UI is bound; otherwise internal. |
| health | conditionally visible | Same as hunger. |

The "conditionally visible" rows mean the world-order rule itself owns an internal `Representation`, but its `Representation` becomes visible when a downstream binding (a UI rule, an overlay, a logger) attaches to it. The base world-order package must keep these internal-only by default so that adopting packages can choose the visibility surface without fighting an already-rendered widget.

## 8. World-order base taxonomy (18 rules)

The base set of world-order rules is fixed at **18** rules, organised in five layers. This list defines the *target shape* of the world-order DAG. It does **not** commit any single PR (including #62) to ship all 18 rules in one batch; rules may land incrementally as long as the resulting graph stays a valid DAG under the rest of this contract.

| Layer | Rule | Capability kind | Minimum required capability kinds |
| --- | --- | --- | --- |
| Foundation | existence | `world-order.existence` | `world.existence` |
| Foundation | time | `world-order.time` | `world-order.base`, `world.base-time` |
| Foundation | space | `world-order.space` | `world-order.base`, `world.space` |
| Foundation | representation | `world-order.representation` | `world.representation` |
| Foundation | state | `world-order.state` | `world.state` |
| Physical | object | `world-order.object` | `world-order.existence`, `world-order.space` |
| Physical | body | `world-order.body` | `world-order.existence`, `world-order.state` |
| Physical | movement | `world-order.movement` | `world-order.space`, `world.movement` |
| Physical | container-possession | `world-order.container_possession` | `world-order.object`, `world-order.state` |
| Social | relationship | `world-order.relationship` | `world-order.existence`, `world-order.state` |
| Social | ownership | `world-order.ownership` | `world-order.object`, `world-order.relationship` |
| Social | action | `world-order.action` | `world-order.body`, `world.basic-action` |
| Resource | resource | `world-order.resource` | `world-order.state` |
| Resource | money | `world-order.money` | `world-order.resource`, `world-order.ownership` |
| Life | food | `world-order.food` | `world-order.object`, `world-order.resource` |
| Life | meal | `world-order.meal` | `world-order.food`, `world-order.action` |
| Life | hunger | `world-order.hunger` | `world-order.body`, `world-order.time` |
| Life | health | `world-order.health` | `world-order.body`, `world-order.state`, `world-order.hunger` |

The rule names and capability kinds in this table are normative for new world-order packages that implement these base rules. A package may add more specific sub-kinds (for example `world-order.money.coinage`) in addition to the listed base kind, but consumers of the base taxonomy should require the listed string. The dependency edges above are the **minimum** target set; packages may add more required kinds, but they may not drop any of these for the same rule once the corresponding rule is implemented under this taxonomy.

The current built-in peaceful-world-order package predates this final taxonomy and implements a related subset (peaceful_foundation, time, time.{morning,noon,night,age}, objects, ownership, money, meal, hunger, body, health). Some existing rule ids and minimum dependencies do not yet match the table exactly. Aligning that package to this target taxonomy is intentionally out of scope for #86 and belongs to #62 or follow-up implementation issues.

## 9. 2D / 3D parity

The 2D runtime (`scripts/game/world_2d_scene.gd`) and the 3D runtime (`scripts/game/world_3d_scene.gd`) share the same `WorldState`, the same package set, and the same rule model. All of the following must hold for both runtimes without divergence:

- the rule graph shape (root vs child, multi-parent edges)
- package dependency rejection and future capability-cycle rejection semantics (§3)
- deterministic snapshot rule-tree ordering and future topological application ordering (§4)
- conflict semantics on stat / relation / event binding / capability, with automatic detection still future work (§5)
- snapshot `rule_tree` shape and the canonical-view contract (§6)
- representation visibility defaults for the world-order base set (§7)

Runtime-specific differences (sprites vs meshes, 2D vs 3D coordinate systems) are concentrated in the providers of `world.space` and the rendering of visible `Representation`s. They must not leak into the world-order DAG itself.

## 10. Validation observations

The following observations are what #62 (and future world-order PRs) should rely on. They are also what the smoke test introduced by #86 checks against the current runtime — see `scripts/tests/rule_composition_invariants_smoke_test.gd`.

1. A multi-parent DAG (a rule that requires more than one capability kind from more than one provider) installs successfully, has a non-empty provider list for every required kind in `resolved_parent_rule_links`, and is reachable as a child of each parent in `rule_tree.nodes_by_rule_id`.
2. A rule whose required capability kind has no provider is **rejected at install time**. The error response carries `missing_required_rule_kinds` listing every unmet kind, and the rule never reaches `installed_rules_by_id`. (If a future change lets a rule slip into `installed_rules_by_id` despite missing kinds — for example through a snapshot restore — `_refresh_rule_relationships` would mark it with `blocked = true`, non-empty `missing_required_rule_kinds`, and `dependency_status != "active"`. Both paths must surface the same diagnostic information.)
3. A package whose `package_dependencies` references an unknown package id is rejected with a clear error naming the missing dependency. Package-id self-loops and cycles between known packages are rejected by `_install_rule_package()` via `install_stack` and produce a `dependency cycle detected` error; this PR documents that behavior but the smoke test only covers the missing-dependency path because it does not add fixture packages.
4. `rule_tree.root_rule_ids` and every `node.child_rule_ids` are sorted ascending. Re-snapshotting the same world produces the same ordering byte-for-byte.
5. `rule_tree.nodes_by_rule_id` always lists each rule exactly once. Shared descendants are not duplicated in this view.
6. `rule_tree.roots` is a tree-friendly rendering only; consumers that need graph shape consult `nodes_by_rule_id`. The two views agree on which rules exist.
7. Multiple rules advertising the same capability kind do not block each other; they coexist as providers and consumers continue to list every matching provider in the relevant parent-link entry.
8. Both the 2D scene and the 3D scene see the same snapshot shape from `get_world_snapshot()`.

Failures of any of these observations are bugs in the runtime or in the package set, not in this contract.

## 11. Out of scope

The following are explicitly **not** redefined or relitigated by #86:

- Default-package immutability. The default package remains a removable / disableable / replaceable initial rule set.
- Engine safety shell. Inspector, restore, and dependency-reporting tools remain available even when world rules collapse.
- World-order package implementation completeness and automatic conflict / capability-cycle detection. #62 and follow-up issues own rule-by-rule delivery and enforcement against this contract.
- UI overlay completion, PoC4 Codex workflow, save/load migration coverage. These remain tracked in their own issues.

When #62 begins implementing the remaining rules in §8, it must reference this document for graph shape, ordering, conflict semantics, and snapshot contract.
