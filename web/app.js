// Веб-версия bip39-pm. Всё вычисляется в браузере тем же WASM-ядром, что у
// CLI и расширения. k_app живёт только в памяти этой вкладки; в localStorage
// лежат зашифрованный индекс (домены, логины, счётчики, политики) и, если
// пользователь создал вход по логину, k_app под мастер-паролем (Argon2id).

import { DEFAULT_POLICY, loadCore, toHex, upsertEntry } from "./core.js";

const INDEX_KEY = "bip39-pm.index";
const VAULTS_KEY = "bip39-pm.vaults";
const AUTOLOCK_MS = 5 * 60 * 1000;
const CLIPBOARD_CLEAR_MS = 30_000;

const $ = (id) => document.getElementById(id);
const core = await loadCore(new URL("pm_core.wasm", import.meta.url));

let kApp = null;
let index = { entries: [] };
let autolockTimer;

function status(text, kind = "") {
  $("status").textContent = text;
  $("status").className = kind;
}

function guarded(fn) {
  return async (...args) => {
    try {
      status("");
      await fn(...args);
    } catch (e) {
      status(e.message, "error");
    }
  };
}

// --- индекс ---

function readStoredIndex() {
  try {
    return localStorage.getItem(INDEX_KEY);
  } catch {
    return null;
  }
}

function persistIndex() {
  try {
    localStorage.setItem(INDEX_KEY, core.encryptIndex(kApp, index));
  } catch (e) {
    throw new Error(`Не удалось сохранить индекс: ${e.message}`);
  }
}

// --- вход по логину ---

function readVaults() {
  try {
    return JSON.parse(localStorage.getItem(VAULTS_KEY)) ?? {};
  } catch {
    return {};
  }
}

function writeVaults(vaults) {
  try {
    if (Object.keys(vaults).length) localStorage.setItem(VAULTS_KEY, JSON.stringify(vaults));
    else localStorage.removeItem(VAULTS_KEY);
  } catch (e) {
    throw new Error(`Не удалось сохранить вход: ${e.message}`);
  }
}

// Та же нормализация логина, что в ядре: NFKC, обрезка, нижний регистр.
const normLogin = (s) => s.normalize("NFKC").trim().toLowerCase();

// Argon2id занимает долю секунды и блокирует поток: сначала показываем статус.
const nextFrame = () => new Promise((r) => requestAnimationFrame(() => setTimeout(r, 0)));

function showSignin(show) {
  const hasVaults = Object.keys(readVaults()).length > 0;
  $("signin").hidden = !(show && hasVaults);
  $("seed").hidden = !$("signin").hidden;
  $("use-signin").hidden = !hasVaults;
  (show && hasVaults ? $("signin-login") : $("mnemonic")).focus();
}

// --- сессия ---

function touch() {
  if (!kApp) return;
  clearTimeout(autolockTimer);
  autolockTimer = setTimeout(lock, AUTOLOCK_MS);
}

function lock() {
  kApp = null;
  index = { entries: [] };
  clearTimeout(autolockTimer);
  for (const id of ["site", "login", "password", "mnemonic", "passphrase", "signin-password", "new-password", "new-password2"])
    $(id).value = "";
  $("password").type = "password";
  $("reveal").textContent = "Показать";
  $("session").hidden = true;
  $("unlocked").hidden = true;
  $("locked").hidden = false;
  showSignin(true);
}

function rememberRequest() {
  if (!$("remember").checked) return null;
  const login = $("new-login").value.trim();
  const password = $("new-password").value;
  if (!login) throw new Error("Укажите логин для входа");
  if ([...password].length < 10) throw new Error("Мастер-пароль должен быть не короче 10 символов");
  if (password !== $("new-password2").value) throw new Error("Мастер-пароли не совпадают");
  return { login, password };
}

const unlock = guarded(async () => {
  const remember = rememberRequest();
  const { k_app, fingerprint } = core.unlock($("mnemonic").value, $("passphrase").value);
  openSession(k_app, fingerprint);
  if (remember) {
    status("Шифрую вход…");
    await nextFrame();
    const { data, login } = core.sealVault(k_app, remember.login, remember.password);
    writeVaults({ ...readVaults(), [login]: data });
    $("remember").checked = false;
    $("remember-fields").hidden = true;
    for (const id of ["new-login", "new-password", "new-password2"]) $(id).value = "";
    status(`Вход для «${login}» создан. Отпечаток: ${fingerprint}`, "ok");
  }
});

const signin = guarded(async () => {
  const login = $("signin-login").value.trim();
  const data = readVaults()[normLogin(login)];
  if (!login || !data) throw new Error("Неверный логин или пароль");
  status("Проверяю…");
  await nextFrame();
  const { k_app, fingerprint } = core.openVault(data, login, $("signin-password").value);
  $("signin-password").value = "";
  openSession(k_app, fingerprint);
});

function openSession(k_app, fingerprint) {
  const stored = readStoredIndex();
  let loaded = { entries: [] };
  if (stored) {
    try {
      loaded = core.decryptIndex(k_app, stored);
    } catch {
      $("reset-index").hidden = false;
      showSignin(false);
      throw new Error("Сохранённый в браузере индекс зашифрован другой seed-фразой или passphrase. Проверьте фразу.");
    }
  }
  kApp = k_app;
  index = loaded;
  $("mnemonic").value = "";
  $("passphrase").value = "";
  $("generated").hidden = true;
  $("reset-index").hidden = true;
  $("fingerprint").textContent = fingerprint;
  $("session").hidden = false;
  $("locked").hidden = true;
  $("unlocked").hidden = false;
  renderAccounts();
  touch();
  $("site").focus();
  status(`Открыто. Сверьте отпечаток: ${fingerprint}`, "ok");
}

// --- форма ---

function policy() {
  return {
    length: Number($("length").value),
    lower: $("lower").checked,
    upper: $("upper").checked,
    digits: $("digits").checked,
    symbols: $("symbols").checked,
  };
}

function currentDomain() {
  const site = $("site").value.trim();
  if (!site) return null;
  try {
    return core.domain(site);
  } catch {
    return null;
  }
}

function applyEntry(entry) {
  const p = entry?.policy ?? DEFAULT_POLICY;
  $("counter").value = entry?.counter ?? 1;
  $("length").value = p.length;
  for (const k of ["lower", "upper", "digits", "symbols"]) $(k).checked = p[k];
}

function findEntry() {
  const domain = currentDomain();
  const login = $("login").value.trim().toLowerCase();
  return index.entries.find((e) => e.domain === domain && e.login === login);
}

function compute() {
  touch();
  const domain = currentDomain();
  $("domain").textContent = domain ?? "—";
  const login = $("login").value;
  if (!kApp || !domain || !login.trim()) {
    $("password").value = "";
    $("check").textContent = "—";
    return null;
  }
  try {
    const r = core.password(kApp, domain, login, Number($("counter").value), policy());
    $("password").value = r.password;
    $("check").textContent = r.check;
    status("");
    return r;
  } catch (e) {
    $("password").value = "";
    $("check").textContent = "—";
    status(e.message, "error");
    return null;
  }
}

// Другой аккаунт: подставляем его сохранённые настройки или значения по умолчанию,
// чтобы версия от предыдущего сайта не перенеслась на новый.
function onIdentityInput() {
  applyEntry(findEntry());
  compute();
}

function saveCurrent(counterOverride) {
  const r = compute();
  if (!r) throw new Error("Укажите сайт и логин");
  const entry = {
    domain: r.domain,
    login: r.login,
    counter: counterOverride ?? Number($("counter").value),
    policy: policy(),
  };
  index = upsertEntry(index, entry);
  persistIndex();
  renderAccounts();
}

// --- список аккаунтов ---

function renderAccounts() {
  const q = $("filter").value.trim().toLowerCase();
  const items = index.entries.filter((e) => !q || e.domain.includes(q) || e.login.includes(q));
  $("count").textContent = index.entries.length ? `· ${index.entries.length}` : "";
  $("empty").hidden = index.entries.length > 0;
  $("filter").hidden = index.entries.length < 6;
  $("accounts").replaceChildren(
    ...items.map((e) => {
      const li = document.createElement("li");
      const open = document.createElement("button");
      open.className = "open";
      const who = document.createElement("span");
      who.className = "who";
      who.textContent = `${e.domain} · ${e.login}`;
      const meta = document.createElement("span");
      meta.className = "meta";
      meta.textContent = `версия ${e.counter} · длина ${e.policy.length}${e.policy.symbols ? "" : " · без символов"}`;
      open.append(who, meta);
      open.addEventListener("click", () => {
        $("site").value = e.domain;
        $("login").value = e.login;
        applyEntry(e);
        compute();
        window.scrollTo({ top: 0, behavior: "smooth" });
      });
      const remove = document.createElement("button");
      remove.className = "remove";
      remove.title = "Удалить из индекса";
      remove.setAttribute("aria-label", `Удалить ${e.domain} ${e.login}`);
      remove.textContent = "✕";
      remove.addEventListener(
        "click",
        guarded(async () => {
          if (!confirm(`Удалить ${e.domain} · ${e.login} из индекса? Пароль не изменится.`)) return;
          index = { ...index, entries: index.entries.filter((x) => x !== e) };
          persistIndex();
          renderAccounts();
        }),
      );
      li.append(open, remove);
      return li;
    }),
  );
}

// --- обработчики ---

$("unlock").addEventListener("click", unlock);
$("mnemonic").addEventListener("keydown", (e) => {
  if (e.key === "Enter" && !e.shiftKey) {
    e.preventDefault();
    unlock();
  }
});
$("passphrase").addEventListener("keydown", (e) => e.key === "Enter" && unlock());
$("signin-submit").addEventListener("click", signin);
for (const id of ["signin-login", "signin-password"])
  $(id).addEventListener("keydown", (e) => e.key === "Enter" && signin());
$("use-seed").addEventListener("click", () => (status(""), showSignin(false)));
$("use-signin").addEventListener("click", () => (status(""), showSignin(true)));
$("remember").addEventListener("change", () => {
  $("remember-fields").hidden = !$("remember").checked;
  if ($("remember").checked) $("new-login").focus();
});
$("forget").addEventListener(
  "click",
  guarded(async () => {
    const login = normLogin($("signin-login").value);
    const vaults = readVaults();
    if (!login || !vaults[login]) throw new Error("Введите логин, вход для которого нужно удалить");
    if (!confirm(`Удалить вход «${login}» с этого устройства? Пароли не изменятся, открыть их можно будет seed-фразой.`)) return;
    delete vaults[login];
    writeVaults(vaults);
    $("signin-password").value = "";
    showSignin(true);
    status("Вход удалён", "ok");
  }),
);
$("lock").addEventListener("click", () => (lock(), status("Заблокировано")));

$("new-seed").addEventListener(
  "click",
  guarded(async () => {
    $("generated-words").textContent = core.generate(24);
    $("generated").hidden = false;
  }),
);

$("reset-index").addEventListener(
  "click",
  guarded(async () => {
    if (!confirm("Удалить из браузера индекс, зашифрованный другой seed? Пароли не изменятся, пропадут только сохранённые версии и настройки.")) return;
    localStorage.removeItem(INDEX_KEY);
    $("reset-index").hidden = true;
    status("Индекс удалён. Откройте снова.");
  }),
);

$("site").addEventListener("input", onIdentityInput);
$("login").addEventListener("input", onIdentityInput);
for (const id of ["counter", "length", "lower", "upper", "digits", "symbols"]) $(id).addEventListener("input", compute);
$("filter").addEventListener("input", renderAccounts);

$("reveal").addEventListener("click", () => {
  const show = $("password").type === "password";
  $("password").type = show ? "text" : "password";
  $("reveal").textContent = show ? "Скрыть" : "Показать";
  touch();
});

$("copy").addEventListener(
  "click",
  guarded(async () => {
    const value = $("password").value;
    if (!value) throw new Error("Укажите сайт и логин");
    await navigator.clipboard.writeText(value);
    status("Скопировано. Буфер очистится через 30 секунд.", "ok");
    setTimeout(async () => {
      try {
        if ((await navigator.clipboard.readText()) === value) await navigator.clipboard.writeText("");
      } catch {
        // Без разрешения на чтение буфера очищаем вслепую, только если вкладка активна.
        if (document.hasFocus()) await navigator.clipboard.writeText("").catch(() => {});
      }
    }, CLIPBOARD_CLEAR_MS);
  }),
);

$("save").addEventListener(
  "click",
  guarded(async () => {
    saveCurrent();
    status("Сохранено в индекс", "ok");
  }),
);

$("rotate").addEventListener(
  "click",
  guarded(async () => {
    if (!compute()) throw new Error("Укажите сайт и логин");
    if (!confirm("Сменить пароль? Новый пароль нужно будет установить на сайте.")) return;
    $("counter").value = Number($("counter").value) + 1;
    saveCurrent();
    status(`Версия ${$("counter").value}. Установите новый пароль на сайте.`, "ok");
  }),
);

$("export").addEventListener(
  "click",
  guarded(async () => {
    if (!index.entries.length) throw new Error("Индекс пуст");
    const hex = core.encryptIndex(kApp, index);
    const bytes = new Uint8Array(hex.match(/../g).map((h) => parseInt(h, 16)));
    const url = URL.createObjectURL(new Blob([bytes], { type: "application/octet-stream" }));
    Object.assign(document.createElement("a"), { href: url, download: "index.pmx" }).click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }),
);

$("import").addEventListener(
  "change",
  guarded(async (event) => {
    const file = event.target.files[0];
    event.target.value = "";
    if (!file) return;
    let incoming;
    try {
      incoming = core.decryptIndex(kApp, toHex(new Uint8Array(await file.arrayBuffer())));
    } catch {
      throw new Error("Файл зашифрован другой seed-фразой или повреждён");
    }
    for (const e of incoming.entries) index = upsertEntry(index, e);
    persistIndex();
    renderAccounts();
    status(`Импортировано записей: ${incoming.entries.length}`, "ok");
  }),
);

for (const ev of ["pointerdown", "keydown"]) document.addEventListener(ev, touch, { passive: true });

lock();
status("");
