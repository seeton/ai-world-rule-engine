# AGENTS

## 大前提

- 日本語で回答を行うこと。
- 基本の開発フローは **issue -> branch -> PR** とする。
- `godot-world/` がアクティブな Godot 4 プロジェクトで、リポジトリルートの Node アプリは issue で明示された場合を除き変更しない。

## Worktree の分離

- 同じ worktree を複数のセッションや agent 間で**同時に**共有しないこと。
- 同じ issue の既存 worktree を後続 run で再利用すること自体は問題ないが、同時に複数セッションで使わないこと。
- アクティブな issue ごとに、必ず別の repo-local worktree を使うこと。
- worktree はこのリポジトリ内の `.agent-workspaces/` 配下に置くこと。`/Users/seeton`、`~`、その他ホームディレクトリ配下には clone や worktree を作らないこと。
- helper script が追跡されていない限り、新規 issue worktree を作るときだけ repo root から `git worktree add .agent-workspaces/issue-<number> -b <branch-name> main` のような実コマンドを使うこと。既存 worktree を再利用するときは、そのディレクトリへ移動し、必要なら `git worktree list` で対応する branch / path を確認すること。

## Repo root main の役割

- repo root の `main` は通常の実装場所ではなく、`origin/main` に追随する基準 checkout として扱うこと。
- 日常の実装・競合解消・検証は issue worktree で行い、repo root の tracked ファイルには原則として変更を残さないこと。
- 意図的な untracked ディレクトリが残っていてもよいが、tracked 変更や未解決競合は issue worktree へ移してから同期すること。
- 状態確認には `bash scripts/agent_guard.sh status` または `bash scripts/worktree.sh root-status` を使うこと。
- repo root を fast-forward 同期するときは `bash scripts/worktree.sh sync-root` を使うこと。

## Issue / PR の所有権

- すべての実装セッションは、必ず 1 つの GitHub issue に対応していなければならない。
- 1 つのアクティブな worktree に複数 issue の scope を混在させないこと。
- 1 つの issue が大きすぎる、または無関係なファイルに広くまたがる場合は、編集前により小さい子 issue に分割すること。
- 同じ issue を複数セッションで同時に編集しないこと。
- 同じ PR を複数セッションから同時に更新しないこと。
- PR を claim したセッションは、その claim を release するまで、その PR への後続 push をすべて所有する。
- `@copilot レビューをお願いします` のコメントは、PR の初回作成時には付けないこと。既存 PR に修正を積んだあとで再レビューを依頼する場合にだけ、PR 上へ追加して再レビュー依頼を明示すること。

## 必須の coordination workflow

このリポジトリには、issue / PR claim や排他 lock 用の helper script が常に追跡されているとは限らない。追跡されていない helper を前提にせず、以下を実施すること。

1. 編集前に、対象 issue と worktree の所有者を issue / PR コメントや作業記録で明示する。
2. PR に更新を push する前に、その PR をどの issue/worktree が担当しているかを明示する。
3. `git checkout` / `git clean` / 依存インストール / server 起動のような repo 全体に影響する操作は、他セッションと同時に走らせない。
4. セッション完了時には、所有権メモや issue / PR コメントを更新して解放する。

もし将来 helper script を使う運用にするなら、その script を同じブランチで追跡対象に追加してから、この文書へ具体名を書くこと。

## Godot の起動とクローズ

- Godot 作業では repo root から直接 `godot --path godot-world` を実行しない。
- issue 用 worktree の `godot-world/` へ移動して `godot --path .` を実行し、必要なら `godot --editor --path .` を使う。
- 作業完了後の issue close は、GitHub 上で対象 issue / PR の状態を確認して行う。
- UI / GM 対話が反応せず GUI から復旧導線へ手が届かないときは、最終防衛地点として `bash scripts/world_cli.sh <issue-number> -- <subcommand>` を使う。詳しくは `godot-world/docs/cli.md` を参照。

## ドキュメント記述ガイド

- トップレベルの docs や wiki ページでは、より深いアーキテクチャや workflow の説明に入る前に、まず **そのゲーム/プロジェクトが何か** を平易な言葉で説明すること。
- `README` 系ページや wiki Home では、プレイヤーや利用者向けの短い要約を冒頭近くに置くことを優先する。
- 平易な要約の後では、現在のプロジェクト事実と roadmap / 将来作業を分けて記述すること。

## リポジトリ全体で排他的に扱う操作

以下の操作は、複数セッションで同時実行してはならない。

- `git checkout`
- `git clean`
- `npm install`
- server startup commands

これらを実行する前に、同じ repo を使う他セッションが動いていないことを確認し、必要なら issue / PR 側で実行中であることを明示すること。

## 運用上の注意

- 別セッションがすでに同じ issue / PR / worktree を使っている場合、そのまま共有しないこと。
- helper script が追跡されていない状態では、存在しない command を手順書へ書き足さないこと。
