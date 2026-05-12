# World Operation API

## このページが扱うこと

`scripts/world_ops/` 配下にある **World Operation layer** の契約をまとめる。CLI / GUI / GM / Codex / automation など**すべての surface はこの API を介してのみ世界を操作する**。CLI 文法や GUI ボタンの違いは surface の問題であり、状態遷移そのものは operation contract で 1 か所に集約する。

この設計は #106 で導入された。

## 階層モデル

```
Surface             CLI parser  /  GUI button  /  GM apply  /  Codex apply  /  automation
                            |
                            ↓ 各 surface は string / form / proposal を
                            ↓ { operation_type, request } に翻訳するだけ
                            |
World Op Dispatcher    scripts/world_ops/dispatcher.gd
                            |
                            ↓ operation_type で routing
                            ↓ validate -> (dry_run | execute)
                            ↓ audit を付与
                            |
Operation Logic     scripts/world_ops/ops/<op>.gd  (validate / dry_run / execute)
                            |
                            ↓
Engine-safe primitives  scripts/cli/inspect_report.gd, scripts/cli/cli_actions.gd
                            |
                            ↓
WorldState / SimulationRuntime
```

**鉄則**: surface は WorldState を直接触らない。Operation logic も WorldState を生で操作せず、engine-safe primitives 経由で叩く。

## 結果スキーマ (uniform)

dispatcher / operation が返す Dictionary は常にこの形:

```
{
  "operation_type": String,             # 例: "DisableRule"
  "status":         String,             # 下記 taxonomy
  "exit_code":      int,                # CLI mapping: 0 / 2 / 3
  "lines":          PackedStringArray,  # human-readable
  "payload":        Dictionary,         # machine-readable (CLI --json で出る本体)
  "diff":           Dictionary,         # before/after summary (空の場合あり)
  "audit": {
    "operation_id": String,             # 例: "DisableRule-142856-8e3f06" (test override 可)
    "timestamp":    String              # ISO-ish
  },
  "rollback": {
    "supported":    bool,
    "hint":         String              # 逆操作の手がかり (例: "Inverse op: EnableRule rule_id=foo")
  },
  "validation": {
    "errors":       PackedStringArray,
    "warnings":     PackedStringArray
  }
}
```

### status taxonomy

operation layer (`WorldOpDispatcher.dispatch`) が返す status は次の 4 種:

- `ok` — execute が成功した。`exit_code: 0`
- `dry_run` — `options.dry_run=true` で実行され、世界は mutate されていない。`exit_code: 0`
- `validation_error` — `validate()` が事前検出した不備 (rule 不在、空 path など)。`exit_code: 2`
- `execution_error` — execute 中にエンジン側で失敗した。`exit_code: 3`

surface adapter (CLI parser など) は **operation layer に届かないメタコマンド** のために追加で 2 種を返す:

- `usage_error` — surface 文法の問題 (未対応サブコマンド、引数不足など)。`exit_code: 2`。`validation_error` と区別される
- `directive` — surface 専用のメタコマンド (`help` / `clear` など)。`exit_code: 0`

`directive` / `usage_error` は CLI 文字列 / GUI ボタン等の surface adapter 層で完結するため dispatcher には届かない。surface 結果を消費する側 (CLI envelope renderer, overlay scrollback, GUI button feedback など) はこの 6 種を扱う前提で実装する。

## Phase 1 で実装済みの operations

| operation_type | request 必須項目 | rollback | 備考 |
| --- | --- | --- | --- |
| `InspectWorld` | (なし) | supported (idempotent) | 完全に read-only。dry_run = execute |
| `EnableRule` | `rule_id: String` | supported (`DisableRule` を逆操作として hint) | rule が無い場合は validation_error |
| `DisableRule` | `rule_id: String` | supported (`EnableRule` を逆操作として hint) | 同上 |
| `ListPackages` | (なし) | supported (read-only) | dry_run = execute |
| `DumpSnapshot` | `path: String` | supported (`LoadSnapshot path=…` を hint) | dry_run はファイル書き込みなし |
| `LoadSnapshot` | `path: String` | not supported (Dump を先取りする運用が必要) | 完全置換のため逆操作不可 |

新しい operation を足すときは:

1. `scripts/world_ops/ops/<name>.gd` を `extends RefCounted` で作る
2. `static func operation_type() -> String`, `validate() / dry_run() / execute()` を実装
3. `scripts/world_ops/dispatcher.gd` の `OPERATION_SCRIPTS` に preload を追加
4. `cli/cli_command_parser.gd` に CLI 文法のマッピングを追加 (CLI から呼びたい場合)
5. `scripts/tests/world_op_dispatcher_smoke_test.gd` に検証ケースを追加

## dispatcher options

```
options = {
  "dry_run":         bool,   # validate + dry_run のみ実行 (mutate しない)
  "audit_id":        String, # operation_id の override (テスト用)
  "audit_timestamp": String  # timestamp の override (テスト用)
}
```

## smoke test

- `godot-world/scripts/tests/world_op_dispatcher_smoke_test.gd` — uniform result shape の検証、validate → execution_error / validation_error の振り分け、dry_run が WorldState を mutate しないこと、audit_id override、unknown operation の扱い、各操作の成功 / 失敗パスを 1 通り。
- `godot-world/scripts/tests/world_op_surface_parity_smoke_test.gd` — CLI parser 経由 (string → request → dispatcher) と direct dispatcher 呼び出しが、同じ operation について `audit` を除く全フィールドで一致することを確認する。**surface 間の drift 検出はここで担保する**。

実行例:

```bash
bash scripts/launch_godot.sh 106 -- --headless --script res://scripts/tests/world_op_dispatcher_smoke_test.gd
bash scripts/launch_godot.sh 106 -- --headless --script res://scripts/tests/world_op_surface_parity_smoke_test.gd
```

## 既存 surface との関係

- **CLI** (`scripts/cli/main.gd` + `scripts/cli/cli_command_parser.gd`): string → operation request の adapter。`--json` 指定時は dispatcher の result envelope (operation_type / status / payload / diff / audit / rollback / validation) をそのまま吐く。`--dry-run` で operation の dry_run を呼べる。
- **In-game text CLI overlay** (将来): #104 / #105 で進めていたものを、本 layer の上に作り直す follow-up が必要。同じ `cli_command_parser.dispatch_string()` を呼べばよい。
- **GUI / GM / Codex** (将来): 同じ `WorldOpDispatcher.dispatch()` を呼ぶことで CLI と同じ状態遷移になる。GUI ボタン / GM 提案を `{ operation_type, request }` に変換する layer をそれぞれの surface 側に置く。

## 設計上の鉄則 (#106 由来)

- **CLI と GUI は同じ UI ではないが、同じ World Operation API の別 surface である**。
- surface は WorldState を直接触らない。
- 各 operation は validate / dry_run / execute の 3 段階を持ち、すべてが uniform result を返す。
- 履歴・差分・rollback ヒントは operation 単位で一本化する (将来の audit log / undo の素地)。
- surface 個別の振る舞いではなく **operation contract の test** で正しさを保証する (`world_op_dispatcher_smoke_test.gd` / `world_op_surface_parity_smoke_test.gd`)。
