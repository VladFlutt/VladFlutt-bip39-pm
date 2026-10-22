import { DEFAULT_POLICY } from "./core.js";

const $ = (id) => document.getElementById(id);
const CLIPBOARD_CLEAR_MS = 30_000;
let entries = [];

async function send(type, payload = {}) {
  const response = await chrome.runtime.sendMessage({ type, ...payload });
  if (!response) throw new Error("Нет ответа от расширения");
  if (response.error) throw new Error(response.error);
  return response.ok;
}

function status(text, isError = false) {
  $("status").textContent = text;
  $("status").classList.toggle("error", isError);
}

async function guarded(fn) {
  try {
    status("");
    await fn();
  } catch (e) {
    status(e.message, true);
  }
}

function policy() {
  return {
    length: Number($("length").value),
    lower: $("lower").checked,
    upper: $("upper").checked,
    digits: $("digits").checked,
    symbols: $("symbols").checked,
  };
}

function params() {
  return { login: $("login").value, counter: Number($("counter").value), policy: policy() };
}

function applyEntry(entry) {
  const p = entry?.policy ?? DEFAULT_POLICY;
  $("counter").value = entry?.counter ?? 1;
  $("length").value = p.length;
  for (const k of ["lower", "upper", "digits", "symbols"]) $(k).checked = p[k];
}

async function refreshPassword() {
  if (!$("login").value.trim()) {
    $("password").value = "";
    $("check").textContent = "—";
    return;
  }
  await guarded(async () => {
    const r = await send("password", params());
    $("password").value = r.password;
    $("check").textContent = r.check;
  });
}

async function showUnlocked(fingerprint) {
  $("locked").hidden = true;
  $("unlocked").hidden = false;
  $("fingerprint").textContent = fingerprint;
  try {
    const ctx = await send("context");
    $("domain").textContent = ctx.domain;
    $("insecure").hidden = !ctx.insecure;
    entries = ctx.entries;
    $("logins").replaceChildren(...entries.map((e) => Object.assign(document.createElement("option"), { value: e.login })));
    $("index-info").textContent = `в индексе: ${ctx.total}`;
    if (entries.length) {
      $("login").value = entries[0].login;
      applyEntry(entries[0]);
    }
    $("login").focus();
    await refreshPassword();
  } catch (e) {
    $("form").hidden = true;
    $("site-error").hidden = false;
    $("site-error").textContent = e.message;
  }
}

function showLocked() {
  $("unlocked").hidden = true;
  $("locked").hidden = false;
  $("mnemonic").focus();
}

$("unlock").addEventListener("click", () =>
  guarded(async () => {
    let fingerprint;
    try {
      ({ fingerprint } = await send("unlock", { mnemonic: $("mnemonic").value, passphrase: $("passphrase").value }));
    } catch (e) {
      $("reset-index").hidden = !e.message.includes("другой seed");
      throw e;
    }
    $("mnemonic").value = "";
    $("passphrase").value = "";
    $("generated").hidden = true;
    await showUnlocked(fingerprint);
    status(`Проверьте отпечаток: ${fingerprint}`);
  }),
);

$("reset-index").addEventListener("click", () =>
  guarded(async () => {
    if (!confirm("Удалить из браузера индекс, зашифрованный другой seed? Пароли не пострадают, пропадут только сохранённые счётчики и настройки.")) return;
    await send("resetIndex");
    $("reset-index").hidden = true;
    status("Индекс удалён, разблокируйте снова");
  }),
);

$("new-seed").addEventListener("click", () =>
  guarded(async () => {
    const { mnemonic } = await send("generate", { words: 24 });
    $("generated-words").textContent = mnemonic;
    $("generated").hidden = false;
  }),
);

$("lock").addEventListener("click", () => guarded(async () => (await send("lock"), showLocked())));

$("login").addEventListener("input", () => {
  const entry = entries.find((e) => e.login === $("login").value.trim().toLowerCase());
  if (entry) applyEntry(entry);
  refreshPassword();
});
for (const id of ["counter", "length", "lower", "upper", "digits", "symbols"]) {
  $(id).addEventListener("input", refreshPassword);
}

$("reveal").addEventListener("click", () => {
  const hidden = $("password").type === "password";
  $("password").type = hidden ? "text" : "password";
  $("reveal").textContent = hidden ? "скрыть" : "показать";
});

$("fill").addEventListener("click", () =>
  guarded(async () => {
    const r = await send("fill", params());
    status(r.filled > 1 ? `Заполнено полей: ${r.filled}` : "Заполнено");
    setTimeout(() => window.close(), 600);
  }),
);

$("copy").addEventListener("click", () =>
  guarded(async () => {
    const value = $("password").value;
    if (!value) throw new Error("Введите логин");
    await navigator.clipboard.writeText(value);
    status("Скопировано. Буфер очистится через 30 с, если окно останется открытым.");
    setTimeout(async () => {
      if ((await navigator.clipboard.readText().catch(() => value)) === value) await navigator.clipboard.writeText("");
      status("Буфер очищен");
    }, CLIPBOARD_CLEAR_MS);
  }),
);

$("save").addEventListener("click", () =>
  guarded(async () => {
    if (!$("login").value.trim()) throw new Error("Введите логин");
    await send("save", params());
    await showUnlocked($("fingerprint").textContent);
    status("Сохранено в индекс");
  }),
);

$("rotate").addEventListener("click", () =>
  guarded(async () => {
    if (!$("login").value.trim()) throw new Error("Введите логин");
    if (!confirm("Сменить пароль? Новый пароль нужно будет установить на сайте.")) return;
    $("counter").value = Number($("counter").value) + 1;
    await send("save", params());
    await refreshPassword();
    status(`Новая версия: ${$("counter").value}. Установите этот пароль на сайте.`);
  }),
);

$("export").addEventListener("click", () =>
  guarded(async () => {
    const { data } = await send("exportIndex");
    if (!data) throw new Error("Индекс пуст");
    const bytes = new Uint8Array(data.match(/../g).map((h) => parseInt(h, 16)));
    const url = URL.createObjectURL(new Blob([bytes], { type: "application/octet-stream" }));
    Object.assign(document.createElement("a"), { href: url, download: "index.pmx" }).click();
    URL.revokeObjectURL(url);
  }),
);

$("import").addEventListener("change", (event) =>
  guarded(async () => {
    const file = event.target.files[0];
    if (!file) return;
    const bytes = new Uint8Array(await file.arrayBuffer());
    const data = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
    const r = await send("importIndex", { data });
    await showUnlocked($("fingerprint").textContent);
    status(`Импортировано записей: ${r.imported}, всего: ${r.total}`);
  }),
);

$("mnemonic").addEventListener("keydown", (e) => {
  if (e.key === "Enter" && !e.shiftKey) {
    e.preventDefault();
    $("unlock").click();
  }
});

guarded(async () => {
  const s = await send("status");
  if (s.unlocked) await showUnlocked(s.fingerprint);
  else showLocked();
});
