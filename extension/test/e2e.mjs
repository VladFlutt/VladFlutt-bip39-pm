// Сквозной тест в настоящем Chromium: разблокировка, пароль для текущей
// вкладки, сохранение в индекс, автозаполнение формы, повторное открытие,
// блокировка и отказ чужой seed. Запуск: npm run test:e2e (после build:ext).
//
// В тесте нельзя кликнуть по иконке расширения, поэтому вместо activeTab
// копия расширения получает host_permissions на localhost.
import assert from "node:assert/strict";
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import http from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { chromium } from "playwright";

const ABANDON = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const LOGIN_PAGE = `<!doctype html><meta charset="utf-8"><form>
  <input id="user" type="email"><input id="pw" type="password"><button>Войти</button></form>
  <script>window.inputs = 0; pw.addEventListener("input", () => window.inputs++);</script>`;

const dir = mkdtempSync(join(tmpdir(), "bip39-pm-e2e-"));
const ext = join(dir, "ext");
cpSync(new URL("..", import.meta.url).pathname, ext, { recursive: true });
const manifest = JSON.parse(readFileSync(join(ext, "manifest.json")));
manifest.host_permissions = ["http://localhost/*"];
writeFileSync(join(ext, "manifest.json"), JSON.stringify(manifest));

const server = http.createServer((_, res) => res.end(LOGIN_PAGE)).listen(0);
const port = server.address().port;
const context = await chromium.launchPersistentContext(join(dir, "profile"), {
  headless: true,
  channel: "chromium",
  args: [`--disable-extensions-except=${ext}`, `--load-extension=${ext}`],
});

try {
  const isOurs = (w) => w.url().startsWith("chrome-extension://");
  const worker = context.serviceWorkers().find(isOurs) ?? (await context.waitForEvent("serviceworker", isOurs));
  // Сразу после старта воркера API расширения бывают ещё не подключены.
  for (let i = 0; !(await worker.evaluate(() => !!globalThis.chrome?.windows)); i++) {
    if (i > 50) throw new Error("API расширения не появились в сервис-воркере");
    await new Promise((r) => setTimeout(r, 100));
  }
  const popupUrl = `chrome-extension://${new URL(worker.url()).host}/popup.html`;
  const openPopup = async () => {
    const page = context.waitForEvent("page");
    page.catch(() => {});
    await worker.evaluate((url) => chrome.windows.create({ url, type: "popup", focused: false }), popupUrl);
    return page;
  };

  const site = context.pages()[0] ?? (await context.newPage());
  await site.goto(`http://localhost:${port}/login`);

  const popup = await openPopup();
  await popup.locator("#mnemonic").fill(ABANDON);
  await popup.click("#unlock");
  await popup.waitForSelector("#unlocked:not([hidden])");
  assert.equal(await popup.textContent("#domain"), "localhost");
  assert.equal(await popup.textContent("#fingerprint"), "era-primary-finish");

  await popup.fill("#login", "vlad@mail.ru");
  await popup.waitForFunction(() => document.querySelector("#check").textContent.includes("-"));
  // Совпадает с `pm get localhost vlad@mail.ru`.
  assert.equal(await popup.inputValue("#password"), "n1q$5TmU!x13G#Cgwg~7");

  await popup.fill("#length", "16");
  await popup.uncheck("#symbols");
  await popup.waitForFunction(() => document.querySelector("#password").value.length === 16);
  assert.equal(await popup.inputValue("#password"), "iklKNUa5MOBJ8YSL");
  await popup.click("#save");
  await popup.waitForFunction(() => document.querySelector("#index-info").textContent.includes("1"));

  const closed = popup.waitForEvent("close");
  await popup.click("#fill");
  await closed;
  assert.deepEqual(
    await site.evaluate(() => [user.value, pw.value, window.inputs]),
    ["vlad@mail.ru", "iklKNUa5MOBJ8YSL", 1],
  );

  // Сессия и индекс переживают закрытие окна: настройки подставились сами.
  const again = await openPopup();
  await again.waitForSelector("#unlocked:not([hidden])");
  await again.waitForFunction(() => document.querySelector("#password").value.length === 16);
  assert.equal(await again.inputValue("#login"), "vlad@mail.ru");
  assert.equal(await again.isChecked("#symbols"), false);

  await again.click("#lock");
  await again.waitForSelector("#locked:not([hidden])");
  assert.deepEqual(await worker.evaluate(() => chrome.storage.session.get(null)), {});

  await again.fill("#mnemonic", "legal winner thank year wave sausage worth useful legal winner thank yellow");
  await again.click("#unlock");
  await again.waitForSelector("#reset-index:not([hidden])");
  assert.match(await again.textContent("#status"), /другой seed/);

  console.log("e2e: ok");
} catch (e) {
  console.error("FAIL:", e.message);
  process.exitCode = 1;
} finally {
  await context.close();
  server.close();
  rmSync(dir, { recursive: true, force: true });
}
