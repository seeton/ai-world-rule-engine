# Collapse-safe CLI (Phase 1)

## このページが扱うこと

Godot 内 UI と GM 対話に依存しない、**最終防衛地点としての CLI** の使い方をまとめる。world rule の崩壊や `builtin.space` の無効化で、プレイヤー入力・カメラ・HUD・GM ダイアログのいずれかが反応しなくなったときでも、別プロセスからエンジン状態を観測し、ルールを無効化・再有効化し、スナップショットで状態を退避できるようにする。

普段の運用 (デバッグ・QA・自動化) でも一次操作面として使える。

> **重要 (#106)**: CLI と GUI / GM / Codex / automation は **同じ UI ではないが、同じ World Operation API の別 surface である**。CLI 文法は string → `{ operation_type, request }` への変換であり、実際の状態遷移は `scripts/world_ops/dispatcher.gd` 経由で行われる。各 operation の契約 (validate / dry_run / execute / diff / rollback hint) は [`world_operations.md`](world_operations.md) を参照。

## なぜ別プロセスなのか

CLI も world rule 崩壊に巻き込まれてはいけないので、稼働中の世界には attach せず、必ず `godot --headless` を新規プロセスとして起動する。状態をやり取りしたい場合はスナップショットファイルを介する。

`SimulationRuntime` / `WorldState` の engine-safe API のみを呼び、ティック評価ループは起動時には走らせない (`advance_tick` を明示的に呼ばない)。

## 起動方法

issue worktree から `scripts/world_cli.sh` を使う。`scripts/launch_godot.sh` と同様、repo root から直接 `godot-world` を触ることを拒否する。

```bash
# 例: issue #93 用 worktree から inspect
bash scripts/world_cli.sh 93 -- inspect

# JSON 出力 (CI / 自動化向け)
bash scripts/world_cli.sh 93 --json -- inspect

# 既存スナップショットを読み込んでから操作したい場合
bash scripts/world_cli.sh 93 --snapshot user://collapsed.json -- inspect

# 実行コマンドだけ確認したい (Godot は起動しない)
bash scripts/world_cli.sh 93 --dry-run -- inspect
```

issue worktree 以外 (repo root の `godot-world/` を含む) からの実行は `world_cli.sh` 側で拒否される。AGENTS.md の worktree 強制方針と整合している。

## サブコマンドと対応 operation

CLI 文法 → operation request の対応表。actuation の中身は [`world_operations.md`](world_operations.md) で定義された operation contract に従う。

| サブコマンド | 対応 operation_type | 内容 |
| --- | --- | --- |
| `inspect` | `InspectWorld` | installed rules / installed packages / world clock / 崩壊シグナルを返す。read-only。 |
| `rule enable <rule_id>` | `EnableRule` | 指定ルールの `enabled` を true に。rule 不在は validation_error。 |
| `rule disable <rule_id>` | `DisableRule` | 指定ルールの `enabled` を false に。 |
| `package list` | `ListPackages` | `res://rules/packages` 配下から発見された package を列挙する。 |
| `snapshot dump <path>` | `DumpSnapshot` | `WorldState.save_world_snapshot` で deterministic snapshot を書き出す。 |
| `snapshot load <path>` | `LoadSnapshot` | `WorldState.load_world_snapshot` で現在世界を置換する。 |

`snapshot load` 単独だと load 結果を表示して終わる。観測したい場合は `--snapshot <path> -- inspect` のようにグローバル `--snapshot` 経由で読み込んでから別コマンドを実行する。

## グローバルフラグ

- `--json` : 結果を 1 行 JSON envelope (`operation_type` / `status` / `payload` / `diff` / `audit` / `rollback` / `validation`) で stdout に出す。stderr は人向けログ。Godot 起動バナー行が冒頭に出るため、CI から扱う場合は `tail -n 1` か `grep '^{'` で末尾の JSON 行だけ取り出すこと。
- `--dry-run` : operation の `dry_run` パスを呼び、WorldState を mutate せずに「何が起きるか」だけを返す。
- `--snapshot <path>` : サブコマンドを実行する前にスナップショットを読み込む。
- `--allow-detached-head` : 通常は worktree が detached HEAD だと拒否されるが、意図的に許可する場合に指定する (`world_cli.sh` のオプション)。

## 終了コード

| コード | 意味 |
| --- | --- |
| 0 | 成功 (`status: ok`) または `dry_run` |
| 2 | バリデーションエラー / 使い方エラー (`validation_error`、未対応サブコマンド、引数不足など) |
| 3 | 実行エラー (`execution_error`、エンジン側で実装が失敗した場合) |

> **既存運用との差分**: 以前は「ルール未導入」「snapshot 読み込み失敗」もすべて exit 3 で返していたが、operation layer 導入後は `validate()` で事前検出できるものは exit 2 (`validation_error`)、実際の execute 中に起きた失敗のみ exit 3 (`execution_error`) と切り分けられる。

## inspect の JSON スキーマ (Phase 1)

`--json` 指定時、`inspect` は以下の構造を 1 行で出す。

```json
{
  "world": {
    "world_id": "starter-plaza",
    "world_name": "はじまりの広場",
    "world_mode": "two_d",
    "tick": 0,
    "elapsed_seconds": 0.0
  },
  "installed_rules": [
    {
      "rule_id": "...",
      "name": "...",
      "enabled": true,
      "package_id": "...",
      "requires_rule_kinds": [],
      "provides_rule_kinds": [],
      "resolved_parent_rule_ids": [],
      "missing_required_rule_kinds": []
    }
  ],
  "installed_rule_count": 0,
  "disabled_rule_ids": [],
  "rules_with_unmet_requirements": [],
  "installed_packages": [],
  "installed_package_count": 0,
  "world_status": {
    "has_world_clock": false,
    "has_movement_provider": false,
    "has_input_provider": false,
    "collapse_signals": ["no_installed_rules"]
  },
  "snapshot_loaded_from": ""
}
```

`world_status.collapse_signals` には次のいずれかが入る (複数可):

- `no_installed_rules` — ルールが 1 つも入っていない。
- `disabled_rules_present` — disable 済みルールがある。
- `rules_with_unmet_requirements` — 親ルール kind が未充足のルールがある。

UI が立ち上がらない状態で何が起きているかを判断するための軽量シグナルで、復旧手順を決める入り口として使う。

## 想定する復旧フロー (UI 不能化時)

1. 別ターミナルから `bash scripts/world_cli.sh <issue> --snapshot user://last_known.json -- inspect` を叩いて崩壊状態を観測する。
2. `disabled_rule_ids` / `rules_with_unmet_requirements` / `has_movement_provider` を見て、UI を取り戻すために enable / disable すべきルールを特定する。
3. `bash scripts/world_cli.sh <issue> --snapshot user://last_known.json -- rule disable <暴走ルール>`
   `bash scripts/world_cli.sh <issue> --snapshot user://last_known.json -- snapshot dump user://recovered.json`
4. 修復済みスナップショットを GUI 側のロード導線に渡して再起動する。

`restore` / `package install|remove` / `propose` といった、上流契約に依存するサブコマンドは Phase 2 として別 issue で扱う (#93 の非スコープ参照)。

## smoke test

`godot-world/scripts/tests/cli_smoke_test.gd` が、CLI ディスパッチャーが依存する engine-safe API を直接突いて以下を検証する:

- `set_rule_enabled` の disable/enable が `installed_rules_by_id[*].enabled` に反映されること
- disable 済みルールの effects が `advance_tick` で適用されないこと
- snapshot dump → load の往復で `enabled` フラグが保持されること

実行例:

```bash
bash scripts/launch_godot.sh 93 -- --headless --script res://scripts/tests/cli_smoke_test.gd
```

## 既知の制約 / Phase 2 への TODO

- 稼働中世界への live attach は提供しない。常に `--snapshot` 経由でやりとりする。
- `restore` / `package install|remove` / `propose` は本フェーズでは未実装。それぞれ #92 / #90 / #85・#87・#63 の契約確定後に follow-up で追加する。
- `scripts/cli/main.gd` が依存する WorldState API が今後変わる場合、`cli_smoke_test.gd` を一緒に更新する。
