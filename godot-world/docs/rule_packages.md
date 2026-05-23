# Rule package workflow

Godot World is a small rule-driven world simulation. Rule packages are JSON bundles that add or replace gameplay assumptions without embedding scripts.

## Package format

Each package is a JSON document with:

- `package_id`
- `package_tier` (任意。`foundation` / `bundle` / `capability` のいずれか。後述の階層を明示するときに付ける)
- `display_name`
- `description`
- `version`
- `author`
- `source_repo`
- `source_ref`
- `package_dependencies`
- `forked_from`
- `suggested_pr_target`
- `tags`
- `match_phrases`
- `community`
- `patch`

The `patch` block is intentionally limited to structured operations. This keeps the AI rule compiler safe and reviewable.

When `patch.operations` contains `upsert_rule`, that rule must also include `player_description`. This is the stored player-facing "これは何？" explanation and is treated as part of the canonical rule definition.

## Package tiers (`package_tier`)

「ルールパッケージ」と一口に言っても、実際は次の 3 階層に分かれている。`package_tier` フィールドはこの階層を一語で示すための明示ラベルで、UI / ドキュメント / 会話で同じ単語を使うときの拠り所になる。

| `package_tier` | 日本語呼称 | 役割 | 例 |
| --- | --- | --- | --- |
| `foundation` | **基盤** | 2D / 3D 共通の最小世界前提を提供する。`world.foundation` / `world.existence` / `world.state` / `world.space` / `world.base-time` / `world.movement` / `world.basic-action` などの能力を `provides_capabilities` で公開する。 | `builtin.default_package` |
| `bundle` | **プリセット** (旧称: セット) | 基盤の上に高位の生活秩序 (時間帯・所有・金銭・食事・空腹・体・体力 etc.) をまとめて積む preset。基盤の能力を `requires_capabilities` で要求し、特定 `package_id` ではなく能力で結合する。 | `builtin.peaceful_world_order` |
| `capability` | **機能パッケージ** | 単一の主目的 (体力 / 空腹 / 睡眠 / 時間 / マナ吸収など) だけを扱う追加パッケージ。基盤 / プリセットに依存せず、必要なら自分の中で stat / rule を完結させる。 | `builtin.health`, `builtin.hunger`, `builtin.sleep`, `builtin.time`, `builtin.mana_absorption` |

呼称の使い分け:

- 「基盤」と言ったときは `package_tier == "foundation"` だけを指す。`builtin.default_package` の id 末尾に `_package` が付いていても、これは「Default Package」という固有 display_name の都合で残しているだけで、階層上は基盤 1 つしか存在しない。
- 「プリセット」「セット」と言ったときは `package_tier == "bundle"` を指す。複数のルール群を 1 ファイルに束ねる preset であり、単一機能とは区別する。
- 「機能パッケージ」と言ったときは `package_tier == "capability"` を指す。`builtin.health` のような単一機能の追加 package を意味する。
- 単に「パッケージ」と書くと 3 階層のどれを指しているか曖昧になるため、運用 / docs では原則として階層名 (基盤 / プリセット / 機能パッケージ) を添える。

UI 上はタイルの見出し横に同じラベル (`基盤` / `プリセット` / `機能パッケージ`) を pill 表示するので、利用者は同じ単語で階層を識別できる。

`package_tier` 自体はスキーマ上は任意項目だが、`builtin.default_package` は `foundation`、`builtin.peaceful_world_order` は `bundle` を明示しなければ `godot-world/scripts/validate_repo.py` が拒否する。新しい built-in package を追加するときは、上の 3 値のいずれかを必ず付与すること。

## Rule model invariants

Rule packages eventually compile into the runtime's shared rule model, so package authors should follow these invariants:

- rules form a directed acyclic parent/child prerequisite graph (DAG) rather than a strict tree
- child rules may depend on multiple parent rules
- child rules only apply after all of their parent rules are already applied
- required parent prerequisites cannot be skipped
- deeper descendants can be shared across multiple parent chains in the same graph
- every rule owns a `Representation`, even if that representation is internal-only and not visibly rendered

See `rule_model.md` for the detailed prerequisite-graph and `Representation` rules.

## Codex proposal contract

PoC4 Codex output must not become a rule package or GitHub issue directly. Raw generated text is first normalized into a `codex_rule_proposal_v1` document, validated, and then shown for player / human review.

The proposal contract lives in:

- `godot-world/rules/schema/rule_proposal.schema.json`

See `codex_rule_proposals.md` for the validation gate, review states, issue conversion rules, and safety boundary.

## Player workflow

### 1. Clone an existing package

When a player asks for a common mechanic such as hunger or sleep, the repository scores built-in packages by `tags` and `match_phrases`. If a strong match exists, the compiler returns a `clone_candidate` response with package metadata for future GitHub-style flows.

### 2. Draft a new mechanic

If no strong package matches, or the player explicitly wants a new variant, the compiler returns a `draft_custom_rule_patch` response. That draft:

- uses the same safe package format
- includes generated metadata
- sets `review_status` to `needs_design_review`
- can optionally point to `forked_from`
- can carry a `suggested_pr_target` for future upstream submission

### 2.5. Review in the Godot UI

The GM conversation UI now keeps package review data-driven:

- the latest proposal is shown as editable package JSON before install
- `forked_from`, `suggested_pr_target`, tags, and community metadata stay visible during review
- declarative `install_actions` and deferred operations are listed so the player can see what will apply now vs later
- installation stays blocked until the reviewed package is explicitly approved

### 3. Social workflow

Packages support community metadata:

- `likes`
- `dislikes`
- `alternative_package_ids`

This allows a player to:

1. like or dislike an existing package
2. create an alternative package
3. record that alternative as a fork/variant
4. later submit the result upstream using `suggested_pr_target`

## Example metadata for GitHub-style sync

```json
{
  "package_id": "builtin.hunger",
  "source_repo": "github.com/godot-world/rule-library",
  "source_ref": "refs/heads/main",
  "author": "Godot World Team",
  "version": "1.0.0",
  "forked_from": null,
  "suggested_pr_target": {
    "repo": "github.com/godot-world/rule-library",
    "base_ref": "main",
    "package_id": "builtin.hunger"
  }
}
```

## GitHub contribution model

Use package changes with the same default workflow as the rest of the repo: **issue → repo-local worktree → branch → PR**.

- create or reuse `.agent-workspaces/<issue-or-scope>/` before editing package data
- use `git worktree add .agent-workspaces/<issue-or-scope> -b <branch-name>` when the worktree does not already exist
- reuse that worktree for follow-up commits on the same issue when practical
- do not create extra clones or checkouts in `/Users/seeton`, `~`, or other home-directory paths
- clone an existing package when the mechanic already fits
- fork it when you need a variant and set `forked_from`
- preserve `source_repo` and `source_ref`
- set `suggested_pr_target` when the package should be proposed upstream

Before opening a PR, run `bash godot-world/scripts/validate_repo.sh` from the repository root. It validates package JSON against the checked-in schema and catches static `res://...` / `ExtResource(...)` mistakes without requiring a local Godot install, but it does require a Python 3 interpreter available as `python3`.

For rule package PRs, include:

- the linked issue
- whether the package is new, cloned, or forked
- review notes for gameplay impact
- any follow-up upstream PR target

## Safety notes

- No package contains embedded GDScript.
- The compiler only emits declarative patch operations.
- Human review is expected before a custom draft is merged into gameplay.

## Default package vs. peaceful world order

これは前節「Package tiers」の **基盤 (foundation)** と **プリセット (bundle)** の関係を、具体的な built-in package に落とし込んだものである。`package_tier` フィールドの値はそれぞれ `foundation` / `bundle` と一致する。

`builtin.default_package` is the minimum base-world contract shared by both the 2D and 3D runtimes. It provides the `world.foundation.v1` capabilities:

- `world.existence` for world/entity identity and snapshot visibility
- `world.representation` for visible or internal representation
- `world.state` for mutable world/entity state
- `world.space` for 2D/3D position and proximity assumptions
- `world.base-time` for deterministic tick/time ordering and the world clock
- `world.movement` for changing spatial position
- `world.basic-action` for recording basic intents/actions/results

`builtin.peaceful_world_order` sits above that base contract. It owns higher-level peaceful life order such as time-of-day, object/body grouping, ownership, resources/money, food/meals, hunger, and health. Its rules require `world.*` capability kinds, not concrete `default_package.*` rule ids, so a future alternative package can replace the default provider by exposing the same capabilities.

The default package is **not** an immutable engine invariant. It is an initially installed rule set whose rules are removable, disableable, and replaceable like normal rules. Removing or disabling those rules may leave the world degraded, collapsed, or unobservable; the runtime should expose that state instead of preventing it. Dependency breakage is surfaced through fields such as `missing_required_rule_kinds`, `rule_tree` unresolved nodes, `rule_dependency_status.blocked_rule_ids`, and `rule_dependency_status.inactive_rule_ids`.

The engine safety shell is separate from world rules. Inspector, restore, and dependency-reporting tools may remain available even when world rules collapse, but they must not pretend that default-package rules are protected engine internals.

The world-order composition contract that sits on top of this split — DAG shape, implemented package-dependency rejection, future capability-cycle rejection, deterministic snapshot `rule_tree` view, conflict semantics on stat / relation / event binding / capability, 2D / 3D parity, and the 18-rule base taxonomy targeted by #62 — is defined in [`rule_composition_invariants.md`](rule_composition_invariants.md). New peaceful-world-order rules must satisfy that contract: consumers require capability kinds, providers advertise capability kinds, package cycles remain invalid, and package-id dependencies are treated as initial provider choices rather than permanent coupling.

## Current runtime bridge

`res://scripts/integration/runtime_rule_patch_compiler.gd` compiles the safe package format into the current simulation runtime's simpler `rule_patch` shape without modifying core systems.

- `upsert_stat` compiles into baseline runtime effects with defaults and bounds
- `upsert_rule` with `rule_type = "tick_delta"` compiles into `value_per_second`
- `upsert_rule` with `rule_type = "runtime_rule"` compiles into explicit runtime rules, including `requires_rule_kinds` / `provides_rule_kinds` and `install_actions`
- every `upsert_rule` must include `player_description` so the player can immediately understand what the rule is for
- `package_dependencies` are installed before the requesting package so higher-order packages can rely on shared defaults without re-owning them
- event-driven, threshold, and environment operations are preserved as `deferred_operations` for future core support

The built-in split now uses:

- `builtin.default_package`
  - `world.foundation` (`default-package.base` compatibility alias)
  - `world.existence`
  - `world.representation`
  - `world.state`
  - `world.space`
  - `world.base-time`
  - `world.movement`
  - `world.basic-action`
- `builtin.peaceful_world_order` (initially depends on `builtin.default_package`, but requires `world.*` capabilities)
  - `world-order.base`
  - `world-order.time`
    - `world-order.time.morning`
    - `world-order.time.noon`
    - `world-order.time.night`
    - `world-order.time.age`
  - `world-order.objects`
    - `world-order.objects.ownership`
    - `world-order.objects.money`
      - `world-order.objects.money.meal`
        - `world-order.objects.money.meal.hunger`
  - `world-order.body`
    - `world-order.body.health`
