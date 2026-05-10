# Collapse-safe CLI (Phase 1)

## このページが扱うこと

Godot 内 UI と GM 対話に依存しない、**最終防衛地点としての CLI** の使い方をまとめる。world rule の崩壊や `builtin.space` の無効化で、プレイヤー入力・カメラ・HUD・GM ダイアログのいずれかが反応しなくなったときでも、別プロセスからエンジン状態を観測し、ルールを無効化・再有効化し、スナップショットで状態を退避できるようにする。

普段の運用 (デバッグ・QA・自動化) でも一次操作面として使える。

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

## サブコマンド

| サブコマンド | 内容 |
| --- | --- |
| `inspect` | installed rules / installed packages / world clock / 崩壊シグナルを stdout に出す。 |
| `rule enable <rule_id>` | 指定ルールの `enabled` を true に。 |
| `rule disable <rule_id>` | 指定ルールの `enabled` を false に。`SimulationRuntime` のティックは即座にこのフラグを尊重する。 |
| `package list` | `res://rules/packages` 配下から発見された package を列挙する。 |
| `snapshot dump <path>` | `WorldState.save_world_snapshot` で deterministic snapshot を書き出す。 |
| `snapshot load <path>` | `WorldState.load_world_snapshot` で読み込み、`inspect` 等と組み合わせて状態を再現する。 |

`snapshot load` 単独だと load 結果を表示して終わる。観測したい場合は `--snapshot <path> -- inspect` のようにグローバル `--snapshot` 経由で読み込んでから別コマンドを実行する。

## グローバルフラグ

- `--json` : 結果を 1 行 JSON で stdout に出す。stderr は人向けログに使う。Godot 自体が起動時に `Godot Engine v...` のバナー行を stdout の冒頭に出すため、CI から扱う場合は `tail -n 1` か `grep '^{'` で末尾の JSON 行だけ取り出すこと。
- `--snapshot <path>` : サブコマンドを実行する前にスナップショットを読み込む。
- `--dry-run` : 実行されるコマンドを表示するだけで Godot を起動しない。
- `--allow-detached-head` : 通常は worktree が detached HEAD だと拒否されるが、意図的に許可する場合に指定する。

## 終了コード

| コード | 意味 |
| --- | --- |
| 0 | 成功 (操作が完了した、もしくは inspect が結果を返した) |
| 2 | 使い方エラー (引数不足、未対応サブコマンド等) |
| 3 | ランタイムエラー (ルール未導入、スナップショットファイル不正、保存失敗等) |

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

## In-game の C キー overlay (検証導線)

実際にワールドを崩壊させて headless CLI の挙動を確認するのは現状そう簡単ではない。そのため稼働中のワールドに対して **`C` キー** で in-game overlay を開き、CLI `inspect` と同じレポートを画面で確認できるようにしている。

- overlay と headless CLI は `scripts/cli/inspect_report.gd` という共通モジュールを呼ぶので、表示内容は二重管理にならない
- overlay 上の「スナップショットを保存」ボタンで `user://cli_inspect_<timestamp>.json` に書き出せる。headless CLI 側で `bash scripts/world_cli.sh <issue> --snapshot <そのパス> -- inspect` を叩けば、別プロセスからも同じ観測になることを突き合わせ確認できる
- T キー overlay (rule tree) と GM screen とは排他制御される。GM screen が開いている間は C キー入力は無視される
- overlay は read-only な観測 + snapshot dump のみ。`rule disable` / `snapshot load` などの actuation は引き続き headless CLI 側に集約する (UI 崩壊時に届かない overlay に actuation を持たせない)

## 想定する復旧フロー (UI 不能化時)

1. 別ターミナルから `bash scripts/world_cli.sh <issue> --snapshot user://last_known.json -- inspect` を叩いて崩壊状態を観測する。
2. `disabled_rule_ids` / `rules_with_unmet_requirements` / `has_movement_provider` を見て、UI を取り戻すために enable / disable すべきルールを特定する。
3. `bash scripts/world_cli.sh <issue> --snapshot user://last_known.json -- rule disable <暴走ルール>`
   `bash scripts/world_cli.sh <issue> --snapshot user://last_known.json -- snapshot dump user://recovered.json`
4. 修復済みスナップショットを GUI 側のロード導線に渡して再起動する。

`restore` / `package install|remove` / `propose` といった、上流契約に依存するサブコマンドは Phase 2 として別 issue で扱う (#93 の非スコープ参照)。

## smoke test

- `godot-world/scripts/tests/cli_smoke_test.gd` — CLI ディスパッチャーが依存する engine-safe API を直接突き、`set_rule_enabled` の disable/enable、disable 済みルールがティック時に適用されないこと、snapshot dump → load の往復で `enabled` フラグが保持されることを検証する。
- `godot-world/scripts/tests/cli_inspect_overlay_smoke_test.gd` — `inspect_report.gd` (overlay と CLI が共有する集計モジュール) が、ルール導入直後 / disable 直後 / 連続呼び出しで安定したレポートを返すことを検証する。

実行例:

```bash
bash scripts/launch_godot.sh 97 -- --headless --script res://scripts/tests/cli_smoke_test.gd
bash scripts/launch_godot.sh 97 -- --headless --script res://scripts/tests/cli_inspect_overlay_smoke_test.gd
```

## 既知の制約 / Phase 2 への TODO

- 稼働中世界への live attach は提供しない。常に `--snapshot` 経由でやりとりする。
- `restore` / `package install|remove` / `propose` は本フェーズでは未実装。それぞれ #92 / #90 / #85・#87・#63 の契約確定後に follow-up で追加する。
- `scripts/cli/main.gd` が依存する WorldState API が今後変わる場合、`cli_smoke_test.gd` を一緒に更新する。
