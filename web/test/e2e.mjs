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
const types = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".wasm": "application/wasm" };
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
  await page.waitForSelector("#locked:not([hidden])");

  await page.click("#new-seed");
  assert.equal((await page.textContent("#generated-words")).split(" ").length, 24);

  await page.fill("#mnemonic", ABANDON);
  await page.click("#unlock");
  await page.waitForSelector("#unlocked:not([hidden])");
  assert.equal(await page.textContent("#fingerprint"), "era-primary-finish");

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
  await page.fill("#length", "16");
  await page.uncheck("#symbols");
  assert.equal(await page.inputValue("#password"), "oh1fWuHJh2e3emF0");
  await page.click("#save");
  assert.equal(await page.locator("#accounts li").count(), 2);

  // Перезагрузка: ключ забыт, индекс восстанавливается после ввода той же seed.
  // Заодно создаём вход по логину и мастер-паролю.
  await page.reload();
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
