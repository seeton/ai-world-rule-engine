const path = require("path");
const readline = require("node:readline");
const { spawn } = require("node:child_process");
const express = require("express");

const app = express();
const port = Number(process.env.PORT || 3000);
const publicDir = path.join(__dirname, "public");

app.use(express.json({ limit: "1mb" }));
app.use(express.static(publicDir));

const VILLAGER_NAME = "Botaro";
const STATUS_CACHE_TTL_MS = 15_000;
const TURN_TIMEOUT_MS = 120_000;
const DEMO_REPLIES = [
  "こんにちは。今日は村の広場で、どんな空想を育てる？",
  "それ、いいね。私は棒人間だけど、想像力はかなり立派だよ。",
  "この村にはまだ家が少ないから、君の言葉で景色が増えていく感じがする。",
  "うん、その話もっと聞きたい。小さな村でも物語は大きくできるから。",
  "私はここに住む最初の村人。君が話しかけるたび、村が少しずつ生きていくよ。",
];

let statusCache = {
  expiresAt: 0,
  value: null,
  pending: null,
};

function getConfig() {
  return {
    codexBin: process.env.CODEX_BIN || "codex",
    model: process.env.CODEX_MODEL || "gpt-5.4-mini",
    demoFallback: process.env.CODEX_DEMO_FALLBACK !== "false",
    cwd: __dirname,
  };
}

function getVillagerInstructions() {
  return [
    `You are ${VILLAGER_NAME}, the first resident of a tiny AI-only village.`,
    "Reply in natural Japanese.",
    "Keep answers warm, playful, and concise.",
    "Act like a stick-figure villager living in a very small world the user is building with you.",
    "Treat the user as a friendly co-founder of the village.",
    "Stay focused on playful conversation, imagination, and tiny-world roleplay.",
    "Do not talk about policy or system setup unless the user asks directly.",
  ].join(" ");
}

function createDemoReply(message) {
  const trimmed = message.trim();
  const lower = trimmed.toLowerCase();

  if (!trimmed) {
    return "まだ声が聞こえないみたい。短い一言でもくれたら、私はちゃんと返事するよ。";
  }

  if (lower.includes("名前")) {
    return `私は${VILLAGER_NAME}。この村の最初の棒人間だよ。`;
  }

  if (lower.includes("家")) {
    return "家を建てよう。木の棒二本と、やさしい会話があればもう村っぽい。";
  }

  if (lower.includes("村")) {
    return "この村、まだ静かで好きだよ。君が話すたびに住民が増えそう。";
  }

  if (lower.includes("遊")) {
    return "じゃあ遊ぼう。私は広場に立ってるから、君は最初のイベントを決めて。";
  }

  return DEMO_REPLIES[Math.floor(Math.random() * DEMO_REPLIES.length)];
}

function buildStatusDetail(status, config) {
  if (status.ready) {
    const plan = status.planType ? ` / ${status.planType}` : "";
    return `Codex app-server / ${status.accountLabel}${plan} / ${config.model}`;
  }

  if (status.detail) {
    return status.detail;
  }

  return "Codex app-server status unavailable";
}

function buildStatusPayload(status, config) {
  const activeMode = status.ready ? "codex" : config.demoFallback ? "demo" : "offline";

  return {
    villager: VILLAGER_NAME,
    mode: activeMode,
    preferredMode: "codex",
    model: status.ready ? config.model : null,
    provider: {
      name: "codex-app-server",
      ready: status.ready,
      detail: buildStatusDetail(status, config),
      accountType: status.accountType,
      accountLabel: status.accountLabel,
      planType: status.planType,
      authRequired: status.authRequired,
      usageLimited: status.usageLimited,
      fallbackEnabled: config.demoFallback,
    },
  };
}

function createCodexError(message, code, extra = {}) {
  const error = new Error(message);
  error.code = code;
  Object.assign(error, extra);
  return error;
}

class CodexRpcSession {
  constructor(config) {
    this.config = config;
    this.nextId = 1;
    this.pendingRequests = new Map();
    this.notificationListeners = new Set();
    this.closed = false;

    this.proc = spawn(config.codexBin, ["app-server"], {
      cwd: config.cwd,
      stdio: ["pipe", "pipe", "pipe"],
    });

    this.stdout = readline.createInterface({ input: this.proc.stdout });
    this.stderr = "";

    this.proc.stderr.on("data", (chunk) => {
      this.stderr += chunk.toString();
    });

    this.stdout.on("line", (line) => {
      this.handleLine(line);
    });

    this.proc.on("exit", (code, signal) => {
      const suffix = this.stderr.trim() ? ` ${this.stderr.trim()}` : "";
      const error = createCodexError(
        `codex app-server exited unexpectedly (${signal || code}).${suffix}`.trim(),
        "codex_process_exit",
      );

      for (const pending of this.pendingRequests.values()) {
        pending.reject(error);
      }

      this.pendingRequests.clear();
    });

    this.proc.on("error", (error) => {
      const wrapped = createCodexError(
        `Failed to start codex app-server: ${error.message}`,
        "codex_spawn_failed",
      );

      for (const pending of this.pendingRequests.values()) {
        pending.reject(wrapped);
      }

      this.pendingRequests.clear();
    });
  }

  handleLine(line) {
    let message;

    try {
      message = JSON.parse(line);
    } catch {
      return;
    }

    if (Object.prototype.hasOwnProperty.call(message, "id")) {
      const pending = this.pendingRequests.get(message.id);
      if (!pending) {
        return;
      }

      this.pendingRequests.delete(message.id);

      if (message.error) {
        pending.reject(
          createCodexError(message.error.message || "Codex request failed.", "codex_rpc_error", {
            rpcError: message.error,
          }),
        );
        return;
      }

      pending.resolve(message.result);
      return;
    }

    if (!message.method) {
      return;
    }

    for (const listener of this.notificationListeners) {
      listener(message);
    }
  }

  onNotification(listener) {
    this.notificationListeners.add(listener);
    return () => {
      this.notificationListeners.delete(listener);
    };
  }

  request(method, params) {
    const id = this.nextId++;

    return new Promise((resolve, reject) => {
      this.pendingRequests.set(id, { resolve, reject });

      const payload = params === undefined ? { method, id } : { method, id, params };
      this.proc.stdin.write(`${JSON.stringify(payload)}\n`, (error) => {
        if (!error) {
          return;
        }

        this.pendingRequests.delete(id);
        reject(
          createCodexError(`Failed to send request to codex app-server: ${error.message}`, "codex_write_failed"),
        );
      });
    });
  }

  async initialize() {
    await this.request("initialize", {
      clientInfo: {
        name: "ai_village_poc",
        title: "AI Village PoC",
        version: "0.2.0",
      },
      capabilities: null,
    });
  }

  async close() {
    if (this.closed) {
      return;
    }

    this.closed = true;
    this.stdout.close();

    if (this.proc.exitCode !== null) {
      return;
    }

    await new Promise((resolve) => {
      const timer = setTimeout(() => {
        if (this.proc.exitCode === null) {
          this.proc.kill("SIGKILL");
        }
      }, 1_000);

      this.proc.once("exit", () => {
        clearTimeout(timer);
        resolve();
      });

      this.proc.kill("SIGTERM");
    });
  }
}

async function withCodexSession(config, work) {
  const session = new CodexRpcSession(config);

  try {
    await session.initialize();
    return await work(session);
  } finally {
    await session.close();
  }
}

async function probeCodexStatus(config) {
  return withCodexSession(config, async (session) => {
    const [accountResponse, authResponse, rateLimitResponse] = await Promise.all([
      session.request("account/read", { refreshToken: false }),
      session.request("getAuthStatus", { includeToken: false, refreshToken: false }),
      session.request("account/rateLimits/read"),
    ]);

    const account = accountResponse.account;
    const accountType = account?.type || null;
    const planType = account?.type === "chatgpt" ? account.planType : null;
    const accountLabel =
      account?.type === "chatgpt"
        ? "ChatGPT account"
        : account?.type === "apiKey"
          ? "API key"
          : "Not signed in";

    const rateLimits = rateLimitResponse.rateLimitsByLimitId?.premium || rateLimitResponse.rateLimits;
    const usageLimited = Boolean(rateLimits?.rateLimitReachedType);
    const authRequired = Boolean(authResponse.requiresOpenaiAuth);

    let detail = null;

    if (!account) {
      detail = "Codex に未ログインです。`codex login` を実行してください。";
    } else if (usageLimited) {
      detail = "Codex の利用上限に達しています。ChatGPT 側の利用枠または credits を確認してください。";
    }

    return {
      ready: Boolean(account) && !usageLimited,
      detail,
      accountType,
      accountLabel,
      planType,
      authRequired,
      usageLimited,
    };
  });
}

async function getCachedCodexStatus(forceRefresh = false) {
  const now = Date.now();

  if (!forceRefresh && statusCache.value && statusCache.expiresAt > now) {
    return statusCache.value;
  }

  if (statusCache.pending) {
    return statusCache.pending;
  }

  const config = getConfig();

  statusCache.pending = probeCodexStatus(config)
    .catch((error) => ({
      ready: false,
      detail:
        error && typeof error.message === "string"
          ? `Codex app-server を使えません: ${error.message}`
          : "Codex app-server を使えません。",
      accountType: null,
      accountLabel: "Unavailable",
      planType: null,
      authRequired: true,
      usageLimited: false,
    }))
    .then((value) => {
      statusCache.value = value;
      statusCache.expiresAt = Date.now() + STATUS_CACHE_TTL_MS;
      statusCache.pending = null;
      return value;
    });

  return statusCache.pending;
}

async function startOrResumeThread(session, config, threadId) {
  if (threadId) {
    try {
      await session.request("thread/resume", {
        threadId,
        persistExtendedHistory: true,
        excludeTurns: true,
      });
    } catch (error) {
      throw createCodexError(
        "Saved thread could not be resumed.",
        "codex_thread_resume_failed",
        { cause: error },
      );
    }

    return threadId;
  }

  const response = await session.request("thread/start", {
    model: config.model,
    cwd: config.cwd,
    approvalPolicy: "never",
    permissionProfile: { type: "disabled" },
    developerInstructions: getVillagerInstructions(),
    ephemeral: false,
    experimentalRawEvents: false,
    persistExtendedHistory: true,
  });

  return response.thread.id;
}

async function runCodexTurn(session, threadId, message) {
  return new Promise((resolve, reject) => {
    let activeTurnId = null;
    let reply = "";
    let completedReply = "";
    let pendingNotificationError = null;
    let done = false;

    const finish = (error, value) => {
      if (done) {
        return;
      }

      done = true;
      clearTimeout(timeout);
      unsubscribe();

      if (error) {
        reject(error);
        return;
      }

      resolve(value);
    };

    const unsubscribe = session.onNotification((notification) => {
      const { method, params } = notification;

      if (params?.threadId !== threadId) {
        return;
      }

      if (activeTurnId && params.turnId && params.turnId !== activeTurnId) {
        return;
      }

      if (method === "item/agentMessage/delta") {
        reply += params.delta;
        return;
      }

      if (method === "item/completed" && params.item?.type === "agentMessage") {
        completedReply = params.item.text || completedReply;
        return;
      }

      if (method === "error") {
        pendingNotificationError = createCodexError(params.error.message, params.error.codexErrorInfo || "codex_turn_error", {
          codexErrorInfo: params.error.codexErrorInfo,
          additionalDetails: params.error.additionalDetails,
        });
        return;
      }

      if (method !== "turn/completed") {
        return;
      }

      const turn = params.turn;
      const text = completedReply || reply;

      if (turn.status === "completed" && text.trim()) {
        finish(null, {
          reply: text.trim(),
          turnId: turn.id,
        });
        return;
      }

      if (turn.status === "completed") {
        finish(createCodexError("Codex returned an empty reply.", "codex_empty_reply"));
        return;
      }

      if (turn.error?.message) {
        finish(
          createCodexError(turn.error.message, turn.error.codexErrorInfo || "codex_turn_failed", {
            codexErrorInfo: turn.error.codexErrorInfo,
            additionalDetails: turn.error.additionalDetails,
          }),
        );
        return;
      }

      finish(pendingNotificationError || createCodexError("Codex turn did not complete successfully.", "codex_turn_incomplete"));
    });

    const timeout = setTimeout(() => {
      finish(createCodexError("Codex reply timed out.", "codex_turn_timeout"));
    }, TURN_TIMEOUT_MS);

    session
      .request("turn/start", {
        threadId,
        input: [
          {
            type: "text",
            text: message,
            text_elements: [],
          },
        ],
      })
      .then((response) => {
        activeTurnId = response.turn.id;
      })
      .catch((error) => {
        finish(error);
      });
  });
}

async function createCodexReply(message, threadId, config) {
  return withCodexSession(config, async (session) => {
    const activeThreadId = await startOrResumeThread(session, config, threadId);
    const turn = await runCodexTurn(session, activeThreadId, message);

    return {
      threadId: activeThreadId,
      reply: turn.reply,
    };
  });
}

app.get("/api/status", async (_req, res) => {
  const config = getConfig();
  const status = await getCachedCodexStatus();

  res.json(buildStatusPayload(status, config));
});

app.post("/api/chat", async (req, res) => {
  const { message, threadId } = req.body ?? {};

  if (typeof message !== "string") {
    res.status(400).json({ error: "message must be a string" });
    return;
  }

  if (threadId !== undefined && threadId !== null && typeof threadId !== "string") {
    res.status(400).json({ error: "threadId must be a string when provided" });
    return;
  }

  const config = getConfig();
  const status = await getCachedCodexStatus();

  if (!status.ready) {
    if (!config.demoFallback) {
      res.status(503).json({
        error: buildStatusDetail(status, config),
        mode: "offline",
      });
      return;
    }

    res.json({
      villager: VILLAGER_NAME,
      mode: "demo",
      threadId: null,
      reply: createDemoReply(message),
      provider: buildStatusPayload(status, config).provider,
    });
    return;
  }

  try {
    const reply = await createCodexReply(message, threadId ?? null, config);

    res.json({
      villager: VILLAGER_NAME,
      mode: "codex",
      threadId: reply.threadId,
      reply: reply.reply,
      provider: buildStatusPayload(status, config).provider,
    });
  } catch (error) {
    statusCache.expiresAt = 0;

    if (error?.code === "codex_thread_resume_failed") {
      res.status(409).json({
        error: "会話スレッドを再開できませんでした。会話をリセットしてやり直してください。",
        resetThread: true,
      });
      return;
    }

    res.status(502).json({
      error: error instanceof Error ? error.message : "Codex chat error",
      codexErrorInfo: error?.codexErrorInfo || null,
    });
  }
});

app.get(/.*/, (_req, res) => {
  res.sendFile(path.join(publicDir, "index.html"));
});

app.listen(port, () => {
  console.log(`Tiny village app listening on http://localhost:${port}`);
});
