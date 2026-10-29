// Сквозной тест веб-приложения в Chromium с теми же заголовками безопасности,
// что на Vercel (CSP из vercel.json). Запуск: npm run test:web (после web/build.sh).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import http from "node:http";
import { extname, join } from "node:path";

import { chromium } from "playwright";

const root = new URL("../dist/", import.meta.url).pathname;
const vercel = JSON.parse(readFileSync(new URL("../../vercel.json", import.meta.url)));
const securityHeaders = vercel.headers.find((h) => h.source === "/(.*)").headers;
const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript",
  ".css": "text/css",
  ".wasm": "application/wasm",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".webmanifest": "application/manifest+json",
};
const ABANDON = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

const server = http
  .createServer((req, res) => {
    const path = req.url === "/" ? "/index.html" : req.url.split("?")[0];
    try {
      const body = readFileSync(join(root, path));
      for (const { key, value } of securityHeaders) res.setHeader(key, value);
      res.setHeader("Content-Type", types[extname(path)] ?? "application/octet-stream");
      res.end(body);
    } catch {
      res.statusCode = 404;
      res.end();
    }
  })
  .listen(0);
const base = `http://localhost:${server.address().port}/`;

const browser = await chromium.launch();
let page;
try {
  const context = await browser.newContext({ permissions: ["clipboard-read", "clipboard-write"] });
  page = await context.newPage();
  const problems = [];
  page.on("pageerror", (e) => problems.push(e.message));
  page.on("console", (m) => m.type() === "error" && problems.push(m.text()));
  const external = [];
  page.on("request", (r) => !r.url().startsWith(base) && !r.url().startsWith("data:") && external.push(r.url()));

  await page.goto(base);
  await page.waitForSelector("#welcome:not([hidden])");
  assert.equal(await page.title(), "ManagerBIP — пароли из seed-фразы");

  // Учебный режим: демо-фраза, подсказки по шагам, в хранилище ничего не пишется.
  await page.click("#mode-learn");
  await page.waitForSelector("#unlocked:not([hidden])");
  assert.equal(await page.isVisible("#demo-badge"), true);
  assert.equal(await page.isVisible("#vault-card"), false);
  assert.equal(await page.textContent("#fingerprint"), "era-primary-finish");
  assert.match(await page.textContent("#coach-step"), /Шаг 1 из \d+/);
  assert.equal(await page.getAttribute("#fingerprint", "class"), "spot");
  const coachSteps = Number((await page.textContent("#coach-step")).match(/из (\d+)/)[1]);
  await page.click("#coach-next");
  assert.equal(await page.textContent("#domain"), "github.com");
  await page.click("#coach-next");
  assert.equal(await page.inputValue("#login"), "demo@mail.ru");
  assert.ok((await page.inputValue("#password")).length === 20);
  await page.click("#coach-back");
  assert.match(await page.textContent("#coach-step"), /Шаг 2 из/);
  for (let i = 2; i < coachSteps; i++) await page.click("#coach-next");
  assert.equal(await page.textContent("#coach-next"), "Начать работу");
  await page.click("#save");
  assert.equal(await page.locator("#accounts li").count(), 1);

  // В обучении функции Pro открыты: секреты, шаблоны, код переноса.
  assert.match(await page.textContent("#pro-status"), /учебном режиме/);
  await page.fill("#secret-label", "карта");
  await page.click("#secret-get");
  assert.equal(await page.inputValue("#secret-value"), "5987");
  await page.click("#secret-save");
  await page.selectOption("#secret-kind", "ssh");
  assert.equal(await page.isHidden("#secret-size-label"), true);
  await page.fill("#secret-label", "github laptop");
  await page.click("#secret-get");
  assert.match(await page.textContent("#secret-public"), /^ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJv18B347hIuVqi6ZQ6S6DHpx082zNUl7P3W8NcYfnQT/);
  await page.click("#secret-save");
  assert.equal(await page.locator("#secrets li").count(), 2);
  await page.locator("#secrets li", { hasText: "карта" }).locator("button.open").click();
  assert.equal(await page.inputValue("#secret-value"), "5987");
  await page.click("#templates .chip:text('Без символов')");
  assert.equal(await page.isChecked("#symbols"), false);
  assert.equal(await page.inputValue("#length"), "20");
  await page.click("#transfer-show");
  const demoCode = await page.inputValue("#transfer-code");
  assert.match(demoCode, /^PMX1:/);
  await page.fill("#transfer-input", demoCode);
  await page.click("#transfer-import");
  assert.match(await page.textContent("#status"), /Добавлено: 0, обновлено: 0, без изменений: 3/);
  assert.deepEqual(await page.evaluate(() => Object.keys(localStorage)), [], "обучение ничего не сохраняет");

  // «Начать работу» после обучения открывает пошаговую настройку.
  await page.click("#coach-next");
  await page.waitForSelector("#wizard:not([hidden])");
  assert.equal(await page.isVisible("#demo-badge"), false);
  assert.equal(await page.locator("#words li").count(), 24);
  // Выбор 12 слов: новая фраза, отметка «записал» сбрасывается.
  await page.check("#wrote");
  await page.click("#words-12");
  assert.equal(await page.locator("#words li").count(), 12);
  assert.equal(await page.isChecked("#wrote"), false);
  await page.click("#words-24");
  assert.equal(await page.locator("#words li").count(), 24);
  assert.equal(await page.isDisabled("#to-verify"), true);
  const words = await page.locator("#words li").allTextContents();
  await page.check("#wrote");
  await page.click("#to-verify");
  await page.waitForSelector("#step-verify:not([hidden])");
  const positions = (await page.locator("#verify-fields label").allTextContents()).map((t) => Number(t.match(/\d+/)[0]) - 1);
  assert.equal(positions.length, 3);
  await page.fill("#verify-0", "wrong");
  await page.fill("#verify-1", words[positions[1]]);
  await page.fill("#verify-2", words[positions[2]]);
  await page.click("#verify-next");
  assert.match(await page.textContent("#status"), new RegExp(`№${positions[0] + 1}`));
  await page.fill("#verify-0", ` ${words[positions[0]].toUpperCase()} `);
  await page.click("#verify-next");
  await page.waitForSelector("#step-vault:not([hidden])");
  assert.equal(await page.locator("#words li").count(), 0, "фраза стёрта со страницы");
  await page.fill("#wiz-login", "Wizard");
  await page.fill("#wiz-password", "a long wizard secret");
  await page.fill("#wiz-password2", "a long wizard secret");
  await page.click("#wiz-vault-save");
  await page.waitForSelector("#step-done:not([hidden])");
  const wizardFingerprint = await page.textContent("#wiz-fingerprint");
  assert.match(wizardFingerprint, /^[a-z]+-[a-z]+-[a-z]+$/);
  await page.click("#wiz-finish");
  await page.waitForSelector("#unlocked:not([hidden])");
  assert.equal(await page.textContent("#fingerprint"), wizardFingerprint);
  assert.equal(await page.isVisible("#vault-card"), true);
  await page.click("#lock");
  await page.waitForSelector("#signin:not([hidden])");
  await page.fill("#signin-login", "wizard");
  await page.fill("#signin-password", "a long wizard secret");
  await page.click("#signin-submit");
  await page.waitForSelector("#unlocked:not([hidden])");
  assert.equal(await page.textContent("#fingerprint"), wizardFingerprint);

  // Дальше — сценарии с известной фразой на чистом устройстве.
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await page.waitForSelector("#welcome:not([hidden])");
  await page.click("#have-seed");
  await page.waitForSelector("#seed:not([hidden])");

  await page.fill("#mnemonic", ABANDON);
  await page.click("#unlock");
  await page.waitForSelector("#unlocked:not([hidden])");
  assert.equal(await page.textContent("#fingerprint"), "era-primary-finish");
  assert.equal(await page.isVisible("#coach"), false);

  // Векторы спецификации v1: URL нормализуется до домена.
  await page.fill("#site", "https://www.GitHub.com/login");
  await page.fill("#login", "Vlad@mail.ru");
  assert.equal(await page.textContent("#domain"), "github.com");
  assert.equal(await page.inputValue("#password"), "q~9Tlw:qOyeSzu?69AUx");
  assert.equal(await page.textContent("#check"), "amused-liquid");

  await page.click("#copy");
  assert.equal(await page.evaluate(() => navigator.clipboard.readText()), "q~9Tlw:qOyeSzu?69AUx");

  page.once("dialog", (d) => d.accept());
  await page.click("#rotate");
  assert.equal(await page.inputValue("#counter"), "2");
  assert.equal(await page.inputValue("#password"), "eITvMChQRH+*gVT-n4FJ");

  await page.fill("#site", "bank.ru");
  await page.fill("#login", "vlad");
  await page.click("#settings summary");
  await page.fill("#length", "16");
  await page.uncheck("#symbols");
  assert.equal(await page.inputValue("#password"), "oh1fWuHJh2e3emF0");
  await page.click("#save");
  assert.equal(await page.locator("#accounts li").count(), 2);

  // Без ключа функции Pro закрыты, чужой ключ не принимается.
  assert.match(await page.textContent("#pro-status"), /Бесплатная версия/);
  assert.equal(await page.isVisible("#pro-badge"), false);
  await page.fill("#secret-label", "карта");
  await page.click("#secret-get");
  assert.match(await page.textContent("#status"), /«Секреты» — функция ManagerBIP Pro/);
  assert.equal(await page.isHidden("#secret-out"), true);
  await page.click("#transfer-show");
  assert.equal(await page.isHidden("#transfer-code"), true);
  assert.equal(await page.locator("#pro-shops a").count(), 1);
  await page.fill("#pro-key", "MBIP-AAAA-BBBB");
  await page.click("#pro-activate");
  assert.match(await page.textContent("#status"), /ключ/);
  assert.equal(await page.evaluate(() => localStorage.getItem("bip39-pm.pro")), null);

  // Настоящий ключ издателя в репозитории не хранится: проверка активации — по переменной окружения.
  if (process.env.PM_TEST_PRO_KEY) {
    await page.fill("#pro-key", process.env.PM_TEST_PRO_KEY);
    await page.click("#pro-activate");
    await page.waitForSelector("#pro-badge:not([hidden])");
    assert.match(await page.textContent("#pro-status"), /Pro активирован/);
    await page.click("#secret-get");
    assert.equal(await page.inputValue("#secret-value"), "5987");
    await page.click("#default-save");
    await page.fill("#site", "new-site.com");
    assert.equal(await page.inputValue("#length"), "16", "правило для новых сайтов");
    await page.fill("#site", "bank.ru");
    page.once("dialog", (d) => d.accept());
    await page.click("#pro-forget");
    assert.equal(await page.evaluate(() => localStorage.getItem("bip39-pm.pro")), null);
  }

  // Перезагрузка: ключ забыт, индекс восстанавливается после ввода той же seed.
  // Заодно создаём вход по логину и мастер-паролю.
  await page.reload();
  await page.waitForSelector("#welcome:not([hidden])");
  await page.click("#have-seed");
  await page.waitForSelector("#seed:not([hidden])");
  assert.equal(await page.isHidden("#signin"), true, "без сохранённых входов форма логина скрыта");
  await page.fill("#mnemonic", ABANDON);
  await page.check("#remember");
  await page.fill("#new-login", "Vlad");
  await page.fill("#new-password", "correct horse battery");
  await page.fill("#new-password2", "correct horse batterY");
  await page.click("#unlock");
  assert.match(await page.textContent("#status"), /не совпадают/);
  assert.equal(await page.isHidden("#unlocked"), true);
  await page.fill("#new-password2", "correct horse battery");
  await page.click("#unlock");
  await page.waitForSelector("#unlocked:not([hidden])");
  await page.waitForFunction(() => document.getElementById("status").textContent.includes("Вход для «vlad» создан"));
  assert.equal(await page.locator("#accounts li").count(), 2);
  const stored = await page.evaluate(() => JSON.stringify(localStorage));
  assert.ok(!stored.includes("abandon"), "seed-фраза не попадает в localStorage");
  assert.ok(!stored.includes("correct horse"), "мастер-пароль не попадает в localStorage");

  // Вход по логину после блокировки и после перезагрузки.
  await page.click("#lock");
  await page.waitForSelector("#signin:not([hidden])");
  await page.reload();
  await page.waitForSelector("#signin:not([hidden])");
  await page.fill("#signin-login", "vlad");
  await page.fill("#signin-password", "wrong password!");
  await page.click("#signin-submit");
  await page.waitForFunction(() => document.getElementById("status").textContent.includes("Неверный логин или пароль"));
  assert.equal(await page.isHidden("#unlocked"), true);
  await page.fill("#signin-login", " VLAD ");
  await page.fill("#signin-password", "correct horse battery");
  await page.press("#signin-password", "Enter");
  await page.waitForSelector("#unlocked:not([hidden])");
  assert.equal(await page.textContent("#fingerprint"), "era-primary-finish");
  assert.equal(await page.locator("#accounts li").count(), 2);
  await page.locator("#accounts li", { hasText: "github.com" }).locator("button.open").click();
  assert.equal(await page.inputValue("#counter"), "2");
  assert.equal(await page.inputValue("#password"), "eITvMChQRH+*gVT-n4FJ");

  await page.click("#lock");
  await page.waitForSelector("#signin:not([hidden])");
  assert.equal(await page.inputValue("#password"), "");
  assert.equal(await page.inputValue("#signin-password"), "");

  // Вход можно создать и в уже открытом приложении (второй логин для той же seed).
  await page.fill("#signin-login", "vlad");
  await page.fill("#signin-password", "correct horse battery");
  await page.click("#signin-submit");
  await page.waitForSelector("#unlocked:not([hidden])");
  await page.click("#vault-open");
  await page.fill("#vault-login", "phone");
  await page.fill("#vault-password", "another long secret");
  await page.fill("#vault-password2", "another long secret");
  await page.click("#vault-save");
  await page.waitForFunction(() => document.getElementById("status").textContent.includes("Вход для «phone» создан"));
  assert.ok(await page.locator("#status").isVisible());
  await page.click("#lock");
  await page.waitForSelector("#signin:not([hidden])");
  await page.fill("#signin-login", "phone");
  await page.fill("#signin-password", "another long secret");
  await page.click("#signin-submit");
  await page.waitForSelector("#unlocked:not([hidden])");
  assert.equal(await page.textContent("#fingerprint"), "era-primary-finish");
  await page.click("#lock");
  await page.waitForSelector("#signin:not([hidden])");
  page.once("dialog", (d) => d.accept());
  await page.fill("#signin-login", "phone");
  await page.click("#forget");
  await page.waitForFunction(() => document.getElementById("status").textContent.includes("Вход удалён"));

  // Удаление входа: остаётся только seed-фраза.
  await page.fill("#signin-login", "vlad");
  page.once("dialog", (d) => d.accept());
  await page.click("#forget");
  await page.waitForSelector("#seed:not([hidden])");
  assert.equal(await page.evaluate(() => localStorage.getItem("bip39-pm.vaults")), null);

  // Чужая seed не открывает индекс и предлагает его удалить.
  await page.fill("#mnemonic", "legal winner thank year wave sausage worth useful legal winner thank yellow");
  await page.click("#unlock");
  await page.waitForSelector("#reset-index:not([hidden])");

  assert.deepEqual(external, [], "внешние запросы");
  assert.deepEqual(problems, [], "ошибки в консоли");
  console.log("web e2e: ok");
} catch (e) {
  console.error("FAIL:", e.message, "status:", await page?.textContent("#status").catch(() => ""));
  process.exitCode = 1;
} finally {
  await browser.close();
  server.close();
}
