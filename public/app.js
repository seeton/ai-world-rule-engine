const chatLog = document.getElementById("chat-log");
const chatForm = document.getElementById("chat-form");
const chatInput = document.getElementById("chat-input");
const sendButton = document.getElementById("send-button");
const modeBadge = document.getElementById("mode-badge");
const modeDetail = document.getElementById("mode-detail");
const speechBubble = document.getElementById("speech-bubble");
const villagerName = document.getElementById("villager-name");

const history = [];
const THREAD_STORAGE_KEY = "ai-village-thread-id";

function getStoredThreadId() {
  return window.localStorage.getItem(THREAD_STORAGE_KEY);
}

function setStoredThreadId(threadId) {
  if (threadId) {
    window.localStorage.setItem(THREAD_STORAGE_KEY, threadId);
    return;
  }

  window.localStorage.removeItem(THREAD_STORAGE_KEY);
}

function addMessage(role, content) {
  const item = document.createElement("article");
  item.className = `message message-${role}`;
  item.textContent = content;
  chatLog.appendChild(item);
  chatLog.scrollTop = chatLog.scrollHeight;
}

function syncSpeechBubble(text) {
  speechBubble.textContent = text;
}

async function loadStatus() {
  const response = await fetch("/api/status");

  if (!response.ok) {
    throw new Error("ステータス取得に失敗しました。");
  }

  const data = await response.json();
  villagerName.textContent = data.villager;
  modeBadge.textContent = data.mode === "codex" ? `Codex mode (${data.model})` : data.mode === "demo" ? "Demo fallback" : "Codex unavailable";
  modeDetail.textContent = data.provider.detail;
}

chatForm.addEventListener("submit", async (event) => {
  event.preventDefault();

  const message = chatInput.value.trim();
  if (!message) {
    return;
  }

  addMessage("user", message);
  history.push({ role: "user", content: message });
  chatInput.value = "";
  sendButton.disabled = true;

  try {
    const response = await fetch("/api/chat", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message,
        history,
        threadId: getStoredThreadId(),
      }),
    });

    const data = await response.json();

    if (!response.ok) {
      if (data.resetThread) {
        setStoredThreadId(null);
      }

      throw new Error(data.error || "会話に失敗しました。");
    }

    addMessage("assistant", data.reply);
    history.push({ role: "assistant", content: data.reply });
    syncSpeechBubble(data.reply);
    setStoredThreadId(data.threadId || null);
    modeBadge.textContent = data.mode === "codex" ? "Codex mode" : "Demo fallback";
    modeDetail.textContent = data.provider?.detail || modeDetail.textContent;
  } catch (error) {
    const messageText = error instanceof Error ? error.message : "不明なエラーが発生しました。";
    addMessage("system", messageText);
    syncSpeechBubble("あっ、今ちょっと声が届かなかったみたい。");
  } finally {
    sendButton.disabled = false;
    chatInput.focus();
  }
});

loadStatus()
  .then(() => {
    addMessage("assistant", "やあ。私はこの村の最初の住民だよ。話しかけてくれたら、この村を一緒に育てられる。");
  })
  .catch((error) => {
    const message = error instanceof Error ? error.message : "初期化に失敗しました。";
    addMessage("system", message);
  });
