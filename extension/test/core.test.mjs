// Ядро через WASM должно давать те же пароли, что Rust CLI и эталон на Python.
// Запуск: node --test extension/test (после extension/build.sh).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { DEFAULT_POLICY, loadCore, upsertEntry } from "../core.js";

const core = await loadCore(readFileSync(new URL("../pm_core.wasm", import.meta.url)));
const ABANDON = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

test("векторы спецификации v1", () => {
  const { k_app: k, fingerprint } = core.unlock(ABANDON);
  assert.equal(fingerprint, "era-primary-finish");
  const cases = [
    ["github.com", "vlad@mail.ru", 1, DEFAULT_POLICY, "q~9Tlw:qOyeSzu?69AUx", "amused-liquid"],
    ["github.com", "vlad@mail.ru", 2, DEFAULT_POLICY, "eITvMChQRH+*gVT-n4FJ", "marble-clarify"],
    ["github.com", "other@mail.ru", 1, DEFAULT_POLICY, "l4nhKOQY$x$E85uidyw4", "consider-glow"],
    ["bank.ru", "vlad", 1, { ...DEFAULT_POLICY, length: 16, symbols: false }, "oh1fWuHJh2e3emF0", "change-want"],
    ["пример.рф", "vlad", 1, { length: 8, lower: false, upper: false, digits: true, symbols: false }, "48777879", "topple-seminar"],
  ];
  for (const [site, login, counter, policy, password, check] of cases) {
    const r = core.password(k, site, login, counter, policy);
    assert.equal(r.password, password, `${site} ${login} ${counter}`);
    assert.equal(r.check, check);
  }
});

test("URL вкладки нормализуется до домена", () => {
  assert.equal(core.domain("https://accounts.google.com/signin?x=1"), "google.com");
  assert.equal(core.domain("https://www.youtube.com/"), "google.com");
  assert.equal(core.domain("http://localhost:3000/login"), "localhost");
});

test("ошибки ядра превращаются в исключения", () => {
  assert.throws(() => core.unlock(ABANDON.replace("about", "abandon")), /seed/);
  const { k_app: k } = core.unlock(ABANDON);
  assert.throws(() => core.password(k, "a.com", "u", 1, { ...DEFAULT_POLICY, length: 4 }), /длина/);
});

test("новая seed-фраза проходит проверку и даёт ключ", () => {
  for (const words of [12, 24]) {
    const m = core.generate(words);
    assert.equal(m.split(" ").length, words);
    assert.match(core.unlock(m).fingerprint, /^[a-z]+-[a-z]+-[a-z]+$/);
  }
  assert.notEqual(core.generate(), core.generate());
});

test("индекс: шифрование, совместимое с CLI, и чужой ключ", () => {
  const { k_app: k } = core.unlock(ABANDON);
  let index = { entries: [] };
  index = upsertEntry(index, { domain: "b.com", login: "u", counter: 1, policy: DEFAULT_POLICY });
  index = upsertEntry(index, { domain: "a.com", login: "u", counter: 2, policy: DEFAULT_POLICY });
  index = upsertEntry(index, { domain: "b.com", login: "u", counter: 3, policy: DEFAULT_POLICY });
  assert.deepEqual(index.entries.map((e) => [e.domain, e.counter]), [["a.com", 2], ["b.com", 3]]);

  const data = core.encryptIndex(k, index);
  assert.ok(data.startsWith("504d495801")); // "PMIX" + версия 1
  assert.deepEqual(core.decryptIndex(k, data), index);
  const other = core.unlock(ABANDON, "TREZOR").k_app;
  assert.throws(() => core.decryptIndex(other, data), /расшифровать/);
});

test("память WASM не растёт при многократных вызовах", () => {
  const { k_app: k } = core.unlock(ABANDON);
  core.password(k, "warmup.com", "u", 1, DEFAULT_POLICY);
  const before = core.memoryBytes?.() ?? 0;
  for (let i = 0; i < 5000; i++) core.password(k, `s${i}.com`, "u", 1, DEFAULT_POLICY);
  const after = core.memoryBytes?.() ?? 0;
  assert.ok(after - before <= 64 * 1024, `рост ${after - before} байт`);
});

test("вход по логину: k_app под мастер-паролем", () => {
  const { k_app: k } = core.unlock(ABANDON);
  const { data, login } = core.sealVault(k, " Vlad ", "correct horse battery");
  assert.equal(login, "vlad");
  assert.ok(data.startsWith("504d565401")); // "PMVT" + версия 1
  assert.equal(core.sealVault(k, "vlad", "correct horse battery").data === data, false, "соль и nonce случайны");
  assert.deepEqual(core.openVault(data, "VLAD", "correct horse battery"), { k_app: k, fingerprint: "era-primary-finish" });
  assert.throws(() => core.openVault(data, "vlad", "correct horse batterY"), /Неверный логин или пароль/);
  assert.throws(() => core.openVault(data, "other", "correct horse battery"), /Неверный логин или пароль/);
  assert.throws(() => core.sealVault(k, "vlad", "short"), /короче 10/);
});

test("Pro: секреты совпадают с векторами ядра", () => {
  const { k_app: k } = core.unlock(ABANDON);
  assert.equal(core.secret(k, { kind: "pin", length: 4 }, "карта", 1).value, "5987");
  assert.equal(core.secret(k, { kind: "pin", length: 6 }, " Карта Сбер ", 1).value, "936802");
  assert.equal(core.secret(k, { kind: "words", count: 4 }, "secret question", 1).value, "rice trade budget staff");
  assert.equal(core.secret(k, { kind: "wifi", length: 20 }, "home wifi", 1).value, "1w2hnpKJyh93chs4N61a");
  const ssh = core.secret(k, { kind: "ssh" }, "github laptop", 1);
  assert.match(ssh.public, /^ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJv18B347hIuVqi6ZQ6S6DHpx082zNUl7P3W8NcYfnQT/);
  assert.match(ssh.value, /BEGIN OPENSSH PRIVATE KEY/);
  assert.throws(() => core.secret(k, { kind: "pin", length: 3 }, "x", 1), /длина PIN/);
});

test("Pro: код переноса вливается, чужие ключи не принимаются", () => {
  const { k_app: k } = core.unlock(ABANDON);
  const src = {
    entries: [{ domain: "github.com", login: "vlad", counter: 3, policy: DEFAULT_POLICY }],
    secrets: [{ label: "карта", kind: "pin", length: 4, counter: 1 }],
    templates: [{ name: "Банк", policy: { ...DEFAULT_POLICY, length: 16, symbols: false } }],
  };
  const code = core.exportCode(k, src);
  assert.match(code, /^PMX1:/);
  const dst = { entries: [{ domain: "github.com", login: "vlad", counter: 1, policy: DEFAULT_POLICY }] };
  const r = core.importCode(k, dst, code);
  assert.deepEqual([r.added, r.updated, r.kept], [2, 1, 0]);
  assert.equal(r.index.entries[0].counter, 3);
  assert.equal(r.index.secrets[0].label, "карта");
  const { k_app: other } = core.unlock(ABANDON, "другая");
  assert.throws(() => core.importCode(other, dst, code));
  assert.throws(() => core.license("MBIP-AAAA"), /ключ/);
});
