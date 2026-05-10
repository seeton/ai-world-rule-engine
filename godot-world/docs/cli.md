# Collapse-safe CLI (Phase 1)

## このページが扱うこと

世界が崩壊しても復旧導線へ届くための CLI 系統をまとめる。CLI 機能は **2 つの階層 (Tier)** に分かれる:

- **Tier 1 (in-game)** — `C` キーで開く in-game overlay。`inspect` の集計表示に加え、ルールの enable/disable とスナップショットの保存・読み込みを直接実行できる。actuation を `scripts/cli/cli_actions.gd` に集約しているので、Tier 2 と同じ engine-safe API 経路を辿る。Godot は生きていて入力も拾える「軽度〜中程度の崩壊」を **ゲーム内で完結** して復旧する一次手段。
- **Tier 2 (headless CLI)** — `bash scripts/world_cli.sh` で起動する別プロセスの CLI。Godot 自体が起動しない / 入力 rule まで死んだ場合のための **最終防衛地点 (last-line-of-defense)**。Tier 1 が立ち上がらない状況でも snapshot 経由で観測・復旧できる。

普段の運用 (デバッグ・QA・自動化) では Tier 1 を一次操作面として使い、Tier 2 は `--json` 出力で CI / バッチ用途に使う。

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

## Tier 1 — In-game C キー overlay

稼働中のワールドに対して **`C` キー** で overlay を開く。表示内容は headless CLI の `inspect` と同じ集計 (共通モジュール `scripts/cli/inspect_report.gd` 経由) で、画面上から actuation も実行できる:

- **ルールの enable/disable**: 各ルール行の「無効化」/「有効化」ボタンが `WorldState.set_rule_enabled` を呼ぶ
- **スナップショット保存**: 「現在の世界を保存」で `user://cli_inspect_<timestamp>.json` に書き出す
- **スナップショット読み込み**: ドロップダウンで `user://cli_inspect_*.json` を選んで「選択を読み込む」で適用する。「再スキャン」でリストを更新できる
- 操作結果は overlay 下部のステータス行に表示される

actuation はすべて `scripts/cli/cli_actions.gd` 経由で行われ、Tier 2 (headless CLI) と同じ関数を呼ぶ。表示と操作のどちらも二重管理にならない。

T キー overlay (rule tree) と GM screen とは排他制御される。GM screen が開いている間は C キー入力は無視される。Tier 1 から復旧しきれない場合は Tier 2 (`bash scripts/world_cli.sh`) に降りる。

### 自動オープン (CollapseWatcher)

`scripts/game/collapse_watcher.gd` が `WorldState` を約 0.5 秒間隔でポーリングし、`world_status.collapse_signals` に**新しいシグナルが立ち上がった瞬間**にだけ overlay を自動で開く。プレイヤーが「世界が壊れたっぽい」を能動的に察知できないケースでも、復旧導線への入り口を見せるための仕組み。

- **トリガ条件**:
  - 既知のシグナルしか無い状態 → 立ち上がっていなければ open しない
  - 起動直後の baseline (`no_installed_rules` のみ) → emit しない (baseline poll は黙って観測)
  - 新たに `disabled_rules_present` / `rules_with_unmet_requirements` が現れた → open
- **抑制**:
  - GM screen が開いている間は auto-open を保留し、GM screen を閉じた直後に保留分を流す
  - プレイヤーが overlay を手動で閉じた直後は、その時の理由 signal について **8 秒のクールダウン** を貼る (同じ理由では再 open しない)
  - 既に overlay が開いていれば再 open しない (badge が積み上がるのを避ける)
- **手動 open との関係**: C キーで開いた overlay には badge は付かない。auto-open の場合のみ overlay 上部に「自動オープン: <理由>」が出て、自動か手動かを区別できる。

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
- `godot-world/scripts/tests/cli_actions_smoke_test.gd` — `cli_actions.gd` (Tier 1 / Tier 2 共有の actuation surface) を経由して set_rule_enabled / save_snapshot / load_snapshot が同じ engine-safe 結果を返すこと、null world や存在しない rule_id でエラーステータスを返すこと、`list_user_snapshots` が `cli_inspect_*.json` プレフィックスのみ拾うことを検証する。
- `godot-world/scripts/tests/collapse_watcher_smoke_test.gd` — `collapse_watcher.gd` の signal-edge 検出を直接突き、初期 baseline で emit しないこと、`disabled_rules_present` が新たに立った瞬間にだけ emit すること、再 poll で重複 emit しないこと、`reset_baseline` で baseline をやり直せることを検証する。

実行例:

```bash
bash scripts/launch_godot.sh 100 -- --headless --script res://scripts/tests/cli_smoke_test.gd
bash scripts/launch_godot.sh 100 -- --headless --script res://scripts/tests/cli_inspect_overlay_smoke_test.gd
bash scripts/launch_godot.sh 100 -- --headless --script res://scripts/tests/cli_actions_smoke_test.gd
bash scripts/launch_godot.sh 100 -- --headless --script res://scripts/tests/collapse_watcher_smoke_test.gd
```

## 既知の制約 / Phase 2 への TODO

- 稼働中世界への live attach は提供しない。常に `--snapshot` 経由でやりとりする。
- `restore` / `package install|remove` / `propose` は本フェーズでは未実装。それぞれ #92 / #90 / #85・#87・#63 の契約確定後に follow-up で追加する。
- `scripts/cli/main.gd` が依存する WorldState API が今後変わる場合、`cli_smoke_test.gd` を一緒に更新する。
