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
try {
  const context = await browser.newContext({ permissions: ["clipboard-read", "clipboard-write"] });
  const page = await context.newPage();
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
  await page.reload();
  await page.waitForSelector("#locked:not([hidden])");
  await page.fill("#mnemonic", ABANDON);
  await page.click("#unlock");
  await page.waitForSelector("#unlocked:not([hidden])");
  assert.equal(await page.locator("#accounts li").count(), 2);
  await page.locator("#accounts li", { hasText: "github.com" }).locator("button.open").click();
  assert.equal(await page.inputValue("#counter"), "2");
  assert.equal(await page.inputValue("#password"), "eITvMChQRH+*gVT-n4FJ");

  await page.click("#lock");
  await page.waitForSelector("#locked:not([hidden])");
  assert.equal(await page.inputValue("#password"), "");

  // Чужая seed не открывает индекс и предлагает его удалить.
  await page.fill("#mnemonic", "legal winner thank year wave sausage worth useful legal winner thank yellow");
  await page.click("#unlock");
  await page.waitForSelector("#reset-index:not([hidden])");

  assert.deepEqual(external, [], "внешние запросы");
  assert.deepEqual(problems, [], "ошибки в консоли");
  console.log("web e2e: ok");
} catch (e) {
  console.error("FAIL:", e.message);
  process.exitCode = 1;
} finally {
  await browser.close();
  server.close();
}
