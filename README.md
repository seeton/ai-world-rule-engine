# AI Village PoC

棒人間の村人と会話するだけの、最小の PoC アプリです。
バックエンドは OpenAI API 直叩きではなく、ローカルの `codex app-server` を経由します。

## Repository layout

- `godot-world/` — active Godot 4 game/simulation project.
- repo root Node app — older PoC kept intact unless an issue explicitly includes it.

## 使い方

```bash
npm i -g @openai/codex
codex login
npm install
npm start
```

ブラウザで `http://localhost:3000` を開くと、村人 `Botaro` と会話できます。

## モード

- **Codex mode**: `codex login` 済みで利用枠があるとき。`codex app-server` へ接続して会話します。
- **Demo fallback**: Codex が未ログイン、起動不可、利用上限到達などのとき。ローカルの簡易応答で画面確認を続けられます。

## 環境変数

- `CODEX_BIN`: `codex` コマンドのパス
- `CODEX_MODEL`: 使用する Codex モデル。既定値は `gpt-5.4-mini`
- `CODEX_DEMO_FALLBACK`: `false` にすると Codex が使えないとき 503 を返します

`.env.example` を参考に設定してください。

## GitHub workflow

Default development flow is **issue → repo-local worktree → branch → PR**.

- Start from a GitHub issue before implementing.
- Create or reuse a repo-local git worktree under `.agent-workspaces/<issue-or-scope>/` and keep branch-specific artifacts there.
- Do not create extra clones in `/Users/seeton`, `~`, or other home-directory paths.
- Use small issue slices so parallel agents can work in separate branches/PRs.
- Keep Godot 4 work under `godot-world/` unless the issue explicitly targets the legacy Node PoC.
- See [`CONTRIBUTING.md`](./CONTRIBUTING.md) for worktree setup, branch naming, PR expectations, multi-agent coordination, and rule-package upstream contribution rules.
