// ManagerBIP — веб-версия bip39-pm. Всё вычисляется в браузере тем же WASM-ядром, что у
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

// Демо-фраза учебного режима: тестовый вектор BIP39, известный всем.
const DEMO_MNEMONIC = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

let kApp = null;
let index = { entries: [] };
let autolockTimer;
// Учебный режим: демо-фраза, подсказки, в localStorage ничего не пишется.
let demo = false;

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
  if (demo) return;
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

const SCREENS = ["welcome", "wizard", "locked", "unlocked"];

function showScreen(name) {
  for (const id of SCREENS) $(id).hidden = id !== name;
  window.scrollTo(0, 0);
}

const hasVaults = () => Object.keys(readVaults()).length > 0;

// Стартовый экран: при сохранённом входе — форма логина, иначе — выбор режима.
function showStart() {
  if (hasVaults()) {
    showScreen("locked");
    showSignin(true);
  } else {
    showScreen("welcome");
  }
}

function showSignin(show) {
  const any = hasVaults();
  $("signin").hidden = !(show && any);
  $("seed").hidden = !$("signin").hidden;
  $("use-signin").hidden = !any;
  (show && any ? $("signin-login") : $("mnemonic")).focus();
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
  demo = false;
  endCoach();
  resetWizard();
  clearTimeout(autolockTimer);
  for (const id of ["site", "login", "password", "mnemonic", "passphrase", "signin-password", "new-password", "new-password2", "vault-password", "vault-password2"])
    $(id).value = "";
  $("password").type = "password";
  $("reveal").textContent = "Показать";
  $("session").hidden = true;
  $("demo-badge").hidden = true;
  $("vault-fields").hidden = true;
  showStart();
}

// Поля «логин, мастер-пароль, повтор» есть в форме seed (new-*) и в открытом
// приложении (vault-*).
function vaultRequest(prefix) {
  const login = $(`${prefix}-login`).value.trim();
  const password = $(`${prefix}-password`).value;
  if (!login) throw new Error("Укажите логин для входа");
  if ([...password].length < 10) throw new Error("Мастер-пароль должен быть не короче 10 символов");
  if (password !== $(`${prefix}-password2`).value) throw new Error("Мастер-пароли не совпадают");
  return { login, password };
}

async function createVault(k_app, { login, password }) {
  status("Шифрую вход…");
  await nextFrame();
  let sealed;
  try {
    sealed = core.sealVault(k_app, login, password);
  } catch (e) {
    throw new Error(`Вход не создан: ${e.message}`);
  }
  writeVaults({ ...readVaults(), [sealed.login]: sealed.data });
  if (readVaults()[sealed.login] !== sealed.data) {
    throw new Error("Вход не создан: браузер не сохранил данные (приватный режим или запрет хранилища?)");
  }
  // Просим браузер не вытеснять хранилище сайта; отказ не мешает работе.
  navigator.storage?.persist?.().catch(() => {});
  return sealed.login;
}

function clearVaultFields(prefix) {
  for (const id of ["login", "password", "password2"]) $(`${prefix}-${id}`).value = "";
}

const unlock = guarded(async () => {
  const remember = $("remember").checked ? vaultRequest("new") : null;
  const { k_app, fingerprint } = core.unlock($("mnemonic").value, $("passphrase").value);
  openSession(k_app, fingerprint);
  if (remember) {
    const login = await createVault(k_app, remember);
    $("remember").checked = false;
    $("remember-fields").hidden = true;
    clearVaultFields("new");
    status(`Вход для «${login}» создан. Отпечаток: ${fingerprint}`, "ok");
  }
});

const saveVault = guarded(async () => {
  const login = await createVault(kApp, vaultRequest("vault"));
  clearVaultFields("vault");
  $("vault-fields").hidden = true;
  status(`Вход для «${login}» создан. В следующий раз войдите по логину и паролю.`, "ok");
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
  // Учебный режим не трогает индекс пользователя.
  const stored = demo ? null : readStoredIndex();
  let loaded = { entries: [] };
  if (stored) {
    try {
      loaded = core.decryptIndex(k_app, stored);
    } catch {
      $("reset-index").hidden = false;
      showScreen("locked");
      showSignin(false);
      throw new Error("Сохранённый в браузере индекс зашифрован другой seed-фразой или passphrase. Проверьте фразу.");
    }
  }
  kApp = k_app;
  index = loaded;
  $("mnemonic").value = "";
  $("passphrase").value = "";
  $("reset-index").hidden = true;
  $("fingerprint").textContent = fingerprint;
  $("session").hidden = false;
  $("demo-badge").hidden = !demo;
  $("vault-card").hidden = demo;
  for (const id of ["site", "login"]) $(id).value = "";
  applyEntry(null);
  compute();
  showScreen("unlocked");
  renderAccounts();
  touch();
  if (!demo) $("site").focus();
  status(`Открыто. Сверьте отпечаток: ${fingerprint}`, "ok");
}

// --- пошаговая настройка ---

const WIZ_STEPS = ["seed", "verify", "vault", "done"];
let wiz = {};

function resetWizard() {
  wiz = {};
  $("words").replaceChildren();
  $("verify-fields").replaceChildren();
  $("wrote").checked = false;
  $("to-verify").disabled = true;
  for (const id of ["wiz-mnemonic", "wiz-passphrase", "wiz-login", "wiz-password", "wiz-password2"]) $(id).value = "";
}

function wizStep(name) {
  const at = WIZ_STEPS.indexOf(name);
  for (const step of WIZ_STEPS) $(`step-${step}`).hidden = step !== name;
  for (const li of document.querySelectorAll(".steps li")) {
    const i = WIZ_STEPS.indexOf(li.dataset.step);
    li.classList.toggle("done", i < at);
    li.classList.toggle("current", i === at);
  }
  // Для существующей фразы проверка записи не нужна.
  document.querySelector('.steps li[data-step="verify"]').hidden = wiz.existing === true;
  wiz.step = name;
  window.scrollTo(0, 0);
}

function wizSeedTab(existing) {
  wiz.existing = existing;
  $("seed-new").setAttribute("aria-selected", String(!existing));
  $("seed-existing").setAttribute("aria-selected", String(existing));
  $("seed-new-pane").hidden = existing;
  $("seed-existing-pane").hidden = !existing;
  if (!existing && !wiz.words) wizGenerate(24);
  wizStep("seed");
  if (existing) $("wiz-mnemonic").focus();
}

// Новая фраза из 12 или 24 слов. Смена длины — новая фраза, отметку «записал» снимаем.
function wizGenerate(count) {
  wiz.words = core.generate(count).split(" ");
  $("words").replaceChildren(
    ...wiz.words.map((w) => Object.assign(document.createElement("li"), { textContent: w })),
  );
  for (const n of [12, 24]) $(`words-${n}`).setAttribute("aria-checked", String(n === count));
  $("wrote").checked = false;
  $("to-verify").disabled = true;
}

function startWizard() {
  resetWizard();
  status("");
  showScreen("wizard");
  wizSeedTab(false);
}

// Три случайных разных позиции для проверки записи.
function pickPositions(n, count) {
  const picked = new Set();
  while (picked.size < count) picked.add(crypto.getRandomValues(new Uint32Array(1))[0] % n);
  return [...picked].sort((a, b) => a - b);
}

function toVerify() {
  wiz.positions = pickPositions(wiz.words.length, 3);
  $("verify-fields").replaceChildren(
    ...wiz.positions.flatMap((pos, i) => {
      const label = Object.assign(document.createElement("label"), { textContent: `Слово №${pos + 1}` });
      label.htmlFor = `verify-${i}`;
      const input = Object.assign(document.createElement("input"), {
        id: `verify-${i}`,
        autocomplete: "off",
        autocapitalize: "off",
        spellcheck: false,
      });
      input.addEventListener("keydown", (e) => e.key === "Enter" && verifyWords());
      return [label, input];
    }),
  );
  wizStep("verify");
  $("verify-0").focus();
}

const verifyWords = guarded(async () => {
  const wrong = wiz.positions.filter((pos, i) => $(`verify-${i}`).value.trim().toLowerCase() !== wiz.words[pos]);
  if (wrong.length) {
    throw new Error(`Не совпадает слово №${wrong.map((p) => p + 1).join(", №")}. Сверьтесь с записью.`);
  }
  deriveWizardKey(wiz.words.join(" "), "");
});

const existingNext = guarded(async () => {
  deriveWizardKey($("wiz-mnemonic").value, $("wiz-passphrase").value);
});

function deriveWizardKey(mnemonic, passphrase) {
  const { k_app, fingerprint } = core.unlock(mnemonic, passphrase);
  wiz.kApp = k_app;
  wiz.fingerprint = fingerprint;
  // Фраза больше не нужна: дальше работаем только с ключом.
  wiz.words = null;
  $("words").replaceChildren();
  $("wiz-mnemonic").value = "";
  $("wiz-passphrase").value = "";
  wizStep("vault");
  $("wiz-login").focus();
}

const wizVaultSave = guarded(async () => {
  const login = await createVault(wiz.kApp, vaultRequest("wiz"));
  clearVaultFields("wiz");
  wizDone(`Вход для «${login}» создан.`);
});

function wizDone(message) {
  $("wiz-fingerprint").textContent = wiz.fingerprint;
  wizStep("done");
  status(message ?? "", "ok");
}

const wizFinish = guarded(async () => {
  const { kApp: k, fingerprint } = wiz;
  resetWizard();
  openSession(k, fingerprint);
});

// --- учебный режим ---

const COACH = [
  {
    target: "fingerprint",
    text: "Вы вошли с демо-фразой. Вверху отпечаток фразы: три слова. При каждом входе сверяйте их: другие слова значат, что фраза введена с ошибкой.",
  },
  {
    target: "site",
    text: "Введите адрес сайта, для которого нужен пароль. Подойдёт и полная ссылка: ManagerBIP сам выделит домен. Для примера мы подставили github.com.",
    fill: { site: "https://github.com/login" },
  },
  {
    target: "login",
    text: "Теперь логин на этом сайте. У разных логинов на одном сайте будут разные пароли.",
    fill: { login: "demo@mail.ru" },
  },
  {
    target: "password-box",
    text: "Пароль готов. Он не хранится нигде: его каждый раз заново вычисляют фраза, сайт и логин. Нажмите «Показать» или «Копировать», чтобы вставить его на сайте.",
  },
  {
    target: "check",
    text: "Проверочные слова пароля. Если на другом устройстве они те же, то и пароль тот же.",
  },
  {
    target: "settings",
    text: "Если сайт требует пароль короче или без спецсимволов, поменяйте настройки здесь. Нестандартные настройки сохраните в индекс, чтобы не вспоминать их.",
    open: "settings",
  },
  {
    target: "rotate",
    text: "Если пароль утёк, нажмите «Сменить пароль»: версия увеличится на 1 и пароль станет новым. Версия запомнится в индексе.",
  },
  {
    target: "accounts-card",
    text: "Индекс — зашифрованный список сайтов с нестандартными настройками. Паролей в нём нет. В учебном режиме он не сохраняется.",
  },
  {
    target: null,
    text: "Обучение пройдено! Теперь можно создать свою seed-фразу и начать пользоваться ManagerBIP по-настоящему.",
    final: true,
  },
];
let coachAt = 0;

function startDemo() {
  demo = true;
  status("");
  const { k_app, fingerprint } = core.unlock(DEMO_MNEMONIC);
  openSession(k_app, fingerprint);
  coachAt = 0;
  $("coach").hidden = false;
  renderCoach();
}

function endCoach() {
  $("coach").hidden = true;
  document.querySelector(".spot")?.classList.remove("spot");
}

function renderCoach() {
  const step = COACH[coachAt];
  document.querySelector(".spot")?.classList.remove("spot");
  for (const [id, value] of Object.entries(step.fill ?? {})) {
    if (!$(id).value) {
      $(id).value = value;
      onIdentityInput();
    }
  }
  if (step.open) $(step.open).open = true;
  $("coach-step").textContent = `Шаг ${coachAt + 1} из ${COACH.length}`;
  $("coach-text").textContent = step.text;
  $("coach-back").hidden = coachAt === 0;
  $("coach-next").textContent = step.final ? "Начать работу" : "Далее";
  if (step.target) {
    const el = $(step.target);
    el.classList.add("spot");
    el.scrollIntoView({ behavior: "smooth", block: "center" });
  }
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
$("vault-open").addEventListener("click", () => {
  $("vault-fields").hidden = !$("vault-fields").hidden;
  if (!$("vault-fields").hidden) $("vault-login").focus();
});
$("vault-save").addEventListener("click", saveVault);
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
$("lock").addEventListener("click", () => {
  const wasDemo = demo;
  lock();
  status(wasDemo ? "Обучение завершено" : "Заблокировано");
});

$("mode-learn").addEventListener("click", guarded(async () => startDemo()));
$("to-learn").addEventListener("click", guarded(async () => startDemo()));
$("mode-start").addEventListener("click", guarded(async () => startWizard()));
$("have-seed").addEventListener("click", () => {
  status("");
  showScreen("locked");
  showSignin(false);
});
$("to-welcome").addEventListener("click", () => (status(""), showScreen("welcome")));

$("seed-new").addEventListener("click", guarded(async () => wizSeedTab(false)));
$("seed-existing").addEventListener("click", guarded(async () => wizSeedTab(true)));
for (const n of [12, 24]) {
  $(`words-${n}`).addEventListener(
    "click",
    guarded(async () => {
      if (wiz.words?.length === n) return;
      wizGenerate(n);
    }),
  );
}
$("wrote").addEventListener("change", () => ($("to-verify").disabled = !$("wrote").checked));
$("to-verify").addEventListener("click", guarded(async () => toVerify()));
$("verify-next").addEventListener("click", verifyWords);
$("verify-back").addEventListener("click", () => (status(""), wizStep("seed")));
$("existing-next").addEventListener("click", existingNext);
$("wiz-vault-save").addEventListener("click", wizVaultSave);
for (const id of ["wiz-login", "wiz-password", "wiz-password2"])
  $(id).addEventListener("keydown", (e) => e.key === "Enter" && wizVaultSave());
$("wiz-vault-skip").addEventListener("click", () => wizDone());
$("wiz-finish").addEventListener("click", wizFinish);
$("wiz-cancel").addEventListener("click", () => {
  if (wiz.words && !confirm("Отменить настройку? Показанная фраза будет забыта.")) return;
  resetWizard();
  status("");
  showStart();
});

$("coach-next").addEventListener(
  "click",
  guarded(async () => {
    if (COACH[coachAt].final) {
      lock();
      startWizard();
      return;
    }
    coachAt += 1;
    renderCoach();
  }),
);
$("coach-back").addEventListener("click", () => {
  coachAt = Math.max(0, coachAt - 1);
  renderCoach();
});
$("coach-exit").addEventListener("click", () => (lock(), status("Обучение завершено")));

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
