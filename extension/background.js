// Сервис-воркер: единственное место, где живёт k_app и вычисляются пароли.
// k_app хранится в chrome.storage.session (только память, очищается при
// закрытии браузера и недоступен content-скриптам) и стирается по таймеру.
// Seed-фраза нигде не сохраняется.

import { DEFAULT_POLICY, loadCore, upsertEntry } from "./core.js";

const AUTOLOCK_ALARM = "autolock";
const AUTOLOCK_MINUTES = 15;

let corePromise;
const core = () => (corePromise ??= loadCore(chrome.runtime.getURL("pm_core.wasm")));

async function session() {
  const { kApp, fingerprint } = await chrome.storage.session.get(["kApp", "fingerprint"]);
  return kApp ? { kApp, fingerprint } : null;
}

async function requireSession() {
  const s = await session();
  if (!s) throw new Error("Менеджер заблокирован");
  // Любое действие продлевает сессию.
  await chrome.alarms.create(AUTOLOCK_ALARM, { delayInMinutes: AUTOLOCK_MINUTES });
  return s;
}

async function loadIndex(kApp) {
  const { index } = await chrome.storage.local.get("index");
  if (!index) return { entries: [] };
  return (await core()).decryptIndex(kApp, index);
}

async function storeIndex(kApp, index) {
  await chrome.storage.local.set({ index: (await core()).encryptIndex(kApp, index) });
}

async function activeTab() {
  // Окно расширения не считается вкладкой: берём активную вкладку обычного окна.
  const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true, windowType: "normal" });
  if (!tab?.url) throw new Error("Нет активной вкладки");
  return tab;
}

/// Домен берётся только из URL вкладки, а не со страницы: так фишинговый
/// сайт получает пароль для своего домена, а не для настоящего.
async function tabDomain(tab) {
  const url = new URL(tab.url);
  if (url.protocol !== "https:" && url.protocol !== "http:") {
    throw new Error("Пароли доступны только на веб-страницах");
  }
  return { domain: (await core()).domain(tab.url), insecure: url.protocol === "http:" && url.hostname !== "localhost" };
}

function normalizePolicy(p) {
  return { ...DEFAULT_POLICY, ...p, length: Number(p?.length ?? DEFAULT_POLICY.length) };
}

const handlers = {
  async status() {
    const s = await session();
    return { unlocked: !!s, fingerprint: s?.fingerprint ?? null };
  },

  async generate({ words }) {
    return { mnemonic: (await core()).generate(words) };
  },

  async unlock({ mnemonic, passphrase }) {
    const { k_app: kApp, fingerprint } = (await core()).unlock(mnemonic, passphrase);
    // Проверяем индекс до сохранения сессии: чужая seed не должна молча
    // перезаписать индекс другого пользователя.
    try {
      await loadIndex(kApp);
    } catch {
      throw new Error("Индекс в браузере зашифрован другой seed-фразой или passphrase. Проверьте отпечаток.");
    }
    await chrome.storage.session.set({ kApp, fingerprint });
    await chrome.alarms.create(AUTOLOCK_ALARM, { delayInMinutes: AUTOLOCK_MINUTES });
    return { fingerprint };
  },

  /// Выход из тупика после смены seed: индекс старой seed не расшифровать.
  async resetIndex() {
    await chrome.storage.local.remove("index");
    return {};
  },

  async lock() {
    await chrome.storage.session.clear();
    await chrome.alarms.clear(AUTOLOCK_ALARM);
    return {};
  },

  async context() {
    const { kApp } = await requireSession();
    const tab = await activeTab();
    const { domain, insecure } = await tabDomain(tab);
    const index = await loadIndex(kApp);
    return { domain, insecure, entries: index.entries.filter((e) => e.domain === domain), total: index.entries.length };
  },

  async password({ login, counter, policy }) {
    const { kApp } = await requireSession();
    const tab = await activeTab();
    const { domain } = await tabDomain(tab);
    return (await core()).password(kApp, domain, login, Number(counter), normalizePolicy(policy));
  },

  async fill({ login, counter, policy }) {
    const { kApp } = await requireSession();
    const tab = await activeTab();
    const { domain } = await tabDomain(tab);
    const result = (await core()).password(kApp, domain, login, Number(counter), normalizePolicy(policy));
    // Перед вставкой убеждаемся, что вкладка не ушла на другой сайт.
    const fresh = await chrome.tabs.get(tab.id);
    if ((await tabDomain(fresh)).domain !== domain) throw new Error("Страница сменилась, повторите");
    const [injection] = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: fillForm,
      args: [login, result.password],
    });
    if (!injection?.result?.filled) throw new Error("На странице не найдено поле пароля");
    return { filled: injection.result.count, check: result.check };
  },

  async save({ login, counter, policy, note }) {
    const { kApp } = await requireSession();
    const { domain } = await tabDomain(await activeTab());
    const c = await core();
    // Ядро нормализует логин так же, как при деривации.
    const normalized = c.password(kApp, domain, login, Number(counter), normalizePolicy(policy));
    const entry = { domain, login: normalized.login, counter: Number(counter), policy: normalizePolicy(policy) };
    if (note) entry.note = note;
    await storeIndex(kApp, upsertEntry(await loadIndex(kApp), entry));
    return { saved: true };
  },

  async remove({ domain, login }) {
    const { kApp } = await requireSession();
    const index = await loadIndex(kApp);
    await storeIndex(kApp, { ...index, entries: index.entries.filter((e) => !(e.domain === domain && e.login === login)) });
    return {};
  },

  async exportIndex() {
    await requireSession();
    const { index } = await chrome.storage.local.get("index");
    return { data: index ?? null };
  },

  /// Импорт файла индекса (формат совместим с CLI `pm`). Записи объединяются.
  async importIndex({ data }) {
    const { kApp } = await requireSession();
    let incoming;
    try {
      incoming = (await core()).decryptIndex(kApp, data);
    } catch {
      throw new Error("Файл зашифрован другой seed-фразой или повреждён");
    }
    let index = await loadIndex(kApp);
    for (const e of incoming.entries) index = upsertEntry(index, e);
    await storeIndex(kApp, index);
    return { imported: incoming.entries.length, total: index.entries.length };
  },
};

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  // Принимаем команды только от страниц самого расширения: у content-скриптов
  // sender.url — адрес веб-страницы.
  if (sender.id !== chrome.runtime.id || !sender.url?.startsWith(chrome.runtime.getURL(""))) return false;
  const handler = handlers[message?.type];
  if (!handler) return false;
  handler(message)
    .then((result) => sendResponse({ ok: result }))
    .catch((e) => sendResponse({ error: e.message }));
  return true;
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === AUTOLOCK_ALARM) handlers.lock();
});

// Выполняется в контексте страницы: заполняет поле(я) пароля и пустое поле логина.
function fillForm(login, password) {
  const visible = (el) => !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length);
  const setValue = (el, value) => {
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set.call(el, value);
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
  };
  const passwords = [...document.querySelectorAll("input[type=password]")].filter(visible);
  if (!passwords.length) return { filled: false };
  const first = passwords[0];
  const form = first.form;
  // Форма регистрации: поле «пароль» и «повторите пароль».
  const targets = form ? passwords.filter((p) => p.form === form) : [first];
  targets.forEach((p) => setValue(p, password));
  if (login) {
    const inputs = [...(form ?? document).querySelectorAll("input")].filter(visible);
    const before = inputs.slice(0, inputs.indexOf(first)).reverse();
    const user = before.find((i) => ["text", "email", "tel", ""].includes(i.type));
    if (user && !user.value) setValue(user, login);
  }
  return { filled: true, count: targets.length };
}
