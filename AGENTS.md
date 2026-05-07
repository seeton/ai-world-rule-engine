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
- 可能なら repo root から `bash scripts/worktree.sh ensure <issue-number> <branch-name>` を使って worktree を作成または再利用すること。

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

## 必須の guard workflow

1. 編集前に issue と worktree を claim する。

   ```bash
   bash scripts/agent_guard.sh claim-issue 7 .agent-workspaces/issue-7
   ```

2. PR に更新を push する前に、その PR を claim する。

   ```bash
   bash scripts/agent_guard.sh claim-pr 13 .agent-workspaces/issue-7
   ```

3. リポジトリ全体に影響する安全でない操作は、必ず排他 guard 経由で実行する。

   ```bash
   bash scripts/agent_guard.sh run-exclusive git-checkout -- \
     git -C .agent-workspaces/issue-7 checkout feat/7-validation-tooling

   bash scripts/agent_guard.sh run-exclusive git-clean -- \
     git -C .agent-workspaces/issue-7 clean -fd

   bash scripts/agent_guard.sh run-exclusive npm-install -- \
     npm --prefix .agent-workspaces/issue-7 install

   bash scripts/agent_guard.sh run-exclusive start-server -- \
     bash -lc 'cd .agent-workspaces/issue-7 && npm start'
   ```

4. 現在の claim と lock はいつでも確認できる。

   ```bash
   bash scripts/agent_guard.sh status
   ```

5. セッション完了時に claim を release する。

   ```bash
   bash scripts/agent_guard.sh release-pr 13 .agent-workspaces/issue-7
   bash scripts/agent_guard.sh release-issue 7 .agent-workspaces/issue-7
   ```

## Godot の起動とクローズ

- Godot 作業では repo root から直接 `godot --path godot-world` を実行しない。
- `bash scripts/launch_godot.sh <issue-number>` を使い、必要なら `-- --editor` のように追加フラグを渡す。
- 作業完了後に issue を閉じる場合は、対象 worktree の外から `bash scripts/close_issue.sh <issue-number>` を使う。

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

これらを実行する前に、`scripts/agent_guard.sh` で共有排他ロックを取得すること。

## 運用上の注意

- `claim-issue` が失敗した場合、その issue または worktree はすでに別セッションに所有されている。
- `claim-pr` が失敗した場合、その PR はすでに別セッションに所有されている。
- `run-exclusive` が失敗した場合、リポジトリ全体に影響する安全でない操作を、すでに別セッションが実行中である。
- これらのチェックを手動で迂回しないこと。
