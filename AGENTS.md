# AGENTS

## 大前提
- 日本語で回答を行うこと

## Worktree の分離

- 同じ worktree を複数のセッションや agent 間で共有しないこと。
- アクティブな issue または scope ごとに、必ず別の repo-local worktree を使うこと。
- worktree はこのリポジトリ内の `.agent-workspaces/` 配下に置くこと。`/Users/seeton`、`~`、その他ホームディレクトリ配下には clone や worktree を作らないこと。

## Issue の所有権

- すべての実装セッションは、必ず 1 つの GitHub issue に対応していなければならない。
- 1 つのアクティブな worktree に複数 issue の scope を混在させないこと。
- 1 つの issue が大きすぎる、または無関係なファイルに広くまたがる場合は、編集前により小さい子 issue に分割すること。
- 同じ issue を複数セッションで同時に編集しないこと。

## PR の所有権

- 同じ PR を複数セッションから同時に更新しないこと。
- PR を claim したセッションは、その claim を release するまで、その PR への後続 push をすべて所有する。

## ドキュメント記述ガイド

- トップレベルの docs や wiki ページでは、より深いアーキテクチャ、workflow、コントリビューター向け詳細に入る前に、まず **そのゲーム/プロジェクトが何か** を平易な言葉で説明すること。
- `README` 系ページや wiki Home では、プレイヤーや利用者向けの短い要約を冒頭近くに置くことを優先する。
- 平易な要約の後では、現在のプロジェクト事実と roadmap / 将来作業を分けて記述すること。

## リポジトリ全体で排他的に扱う操作

以下の操作は、複数セッションで同時実行してはならない。

- `git checkout`
- `git clean`
- `npm install`
- server startup commands

これらを実行する前に、`scripts/agent_guard.sh` で共有排他ロックを取得すること。

## 必須の guard workflow

1. 編集前に issue と worktree を claim する:

   ```bash
   bash scripts/agent_guard.sh claim-issue 7 .agent-workspaces/issue-7
   ```

2. PR に更新を push する前に、その PR を claim する:

   ```bash
   bash scripts/agent_guard.sh claim-pr 13 .agent-workspaces/issue-7
   ```

3. リポジトリ全体に影響する安全でない操作は、必ず排他 guard 経由で実行する:

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

4. 現在の claim と lock はいつでも確認できる:

   ```bash
   bash scripts/agent_guard.sh status
   ```

5. セッション完了時に claim を release する:

   ```bash
   bash scripts/agent_guard.sh release-pr 13 .agent-workspaces/issue-7
   bash scripts/agent_guard.sh release-issue 7 .agent-workspaces/issue-7
   ```

## 運用上の注意

- `claim-issue` が失敗した場合、その issue または worktree はすでに別セッションに所有されている。
- `claim-pr` が失敗した場合、その PR はすでに別セッションに所有されている。
- `run-exclusive` が失敗した場合、リポジトリ全体に影響する安全でない操作を、すでに別セッションが実行中である。
- これらのチェックを手動で迂回しないこと。
