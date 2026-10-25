# Спецификация bip39-pm v1

Статус: **заморожена**. Любое изменение алгоритма ниже меняет пароли пользователей,
поэтому допускается только новая версия (`v2`) рядом со старой, а не правка `v1`.

## 1. Seed

1. Мнемоника BIP39 (12, 15, 18, 21 или 24 слова, английский словарь), контрольная сумма проверяется.
   Перед разбором: NFKD, нижний регистр, одиночные пробелы между словами.
2. `seed = PBKDF2-HMAC-SHA512(mnemonic, "mnemonic" || passphrase, 2048, 64)` — ровно как в BIP39.
   Passphrase — необязательное «25-е слово», нормализуется NFKD.

## 2. Ключ приложения (BIP85)

1. Мастер-ключ BIP32 из `seed`.
2. Hardened-путь `m/83696968'/20567'/0'` (`20567` = `0x5057`, «PW»).
3. `entropy = HMAC-SHA512(key = "bip-entropy-from-k", msg = privkey_32_bytes)`.
4. `k_app = entropy[0..32]`.

## 3. Нормализация входа

- **Домен.** Строка без схемы дополняется `https://` и разбирается как URL (WHATWG).
  Берётся хост: IDN → punycode, нижний регистр, без завершающей точки.
  IP-адрес используется как есть. Иначе берётся регистрируемый домен (eTLD+1)
  по Public Suffix List из крейта `psl` версии **2.1.244** (зафиксирована).
  Затем таблица алиасов v1: `youtube.com → google.com`, `gmail.com → google.com`.
- **Логин.** Unicode NFKC, обрезка пробелов по краям, нижний регистр.
- **Счётчик.** Целое `u32`, начинается с 1. Смена пароля = счётчик + 1.

## 4. Политика

| Поле | Значения | По умолчанию |
| --- | --- | --- |
| `length` | 8..=64 | 20 |
| `lower` | `abcdefghijklmnopqrstuvwxyz` | вкл. |
| `upper` | `ABCDEFGHIJKLMNOPQRSTUVWXYZ` | вкл. |
| `digits` | `0123456789` | вкл. |
| `symbols` | `!#$%&*+-.:;=?@^_~` | вкл. |

Каноническая строка: `len=<length>;cls=<буквы включённых классов в порядке l,u,d,s>`,
например `len=20;cls=luds`. Нужен хотя бы один класс.

## 5. Ключ сайта

```
info = "bip39-pm/v1/password"
       || u32be(len(domain)) || domain
       || u32be(len(login))  || login
       || u32be(len(policy)) || policy
       || u32be(counter)
k_site = HKDF-SHA256(salt = "bip39-pm/v1", ikm = k_app, info, L = 32)
```

Все строки — UTF-8. Префиксы длины исключают совпадения вида `("a|b", "c")` и `("a", "b|c")`.

## 6. Кодирование пароля

```
stream = HKDF-Expand-SHA256(prk = k_site, info = "bip39-pm/v1/stream", L = 1024)
```

`uniform(n)`: берётся следующий байт `b`; если `b < 256 - 256 mod n`, результат `b mod n`,
иначе байт отбрасывается и берётся следующий.

1. Для каждого включённого класса по порядку `lower, upper, digits, symbols`:
   символ `class[uniform(|class|)]`.
2. Пока длина меньше `length`: символ `union[uniform(|union|)]`, где `union` —
   конкатенация включённых классов в том же порядке.
3. Перемешивание Фишера–Йетса: для `i` от `length-1` до 1: `j = uniform(i+1)`, обмен `i` и `j`.

## 7. Вспомогательные значения

Все через `HKDF-SHA256(salt = "bip39-pm/v1", ikm = k_app, info)`, если не сказано иное.
Слова — английский словарь BIP39, по 11 бит из старших битов 32-битного числа
(у третьего слова младший бит дополняется нулём), через дефис.

| Назначение | info | Выход |
| --- | --- | --- |
| Отпечаток seed | `bip39-pm/v1/fingerprint` | 4 байта → 3 слова |
| Проверочные слова пароля | `bip39-pm/v1/check`, но `prk = k_site` (только Expand) | 4 байта → 2 слова |
| Ключ индекса | `bip39-pm/v1/index-key` | 32 байта |

## 8. Индекс

Файл: `"PMIX"` || `0x01` || nonce (24 байта, случайный) || XChaCha20-Poly1305(JSON).
Первые 5 байт — associated data. JSON: `{"entries":[{"domain","login","counter","policy",
"note"?}], "secrets"?:[…], "templates"?:[{"name","policy"}], "default_policy"?}`.
Необязательные поля появились позже и не пишутся, когда пусты; старые версии их пропускают.
Секрет в индексе: `{"label","kind","length"|"count"?,"counter","note"?}`, значения нет.
Паролей в индексе нет. Без индекса восстанавливаются все пароли со
счётчиком 1 и политикой по умолчанию.

## 8a. Вход по логину (локальный, вне деривации)

Не влияет на пароли: это способ хранить `k_app` на устройстве вместо ввода seed.
Файл: `"PMVT"` || `0x01` || m_kib, t, p (u32 BE) || соль (16) || nonce (24) ||
XChaCha20-Poly1305(k_app). Ключ шифрования — Argon2id v1.3 (мастер-пароль в NFKC, соль,
32 байта), по умолчанию m = 65536 КиБ, t = 3, p = 1; при создании требуется m ≥ 19456.
Associated data: `"bip39-pm/v1/vault"` || первые 33 байта файла || u32be длина || логин
(нормализация из раздела 3). Неверный логин и неверный пароль неразличимы.

## 9. Перенос

Код переноса: `"PMX1:"` || base64url без `=` от файла индекса (раздел 8). Для QR код режется
на кадры `PMQ1:<номер>/<всего>:<часть>`. При слиянии для одного сайта или секрета побеждает
больший счётчик, при равенстве — своя запись.

## 10. Секреты

Метка нормализуется как логин (раздел 3). Вид и его каноническая строка:

| Вид | Каноническая строка | Размер |
| --- | --- | --- |
| PIN | `pin;len=<n>` | 4..=12 цифр |
| Слова | `words;n=<n>` | 3..=8 слов |
| Wi‑Fi | `wifi;len=<n>` | 12..=63 символа |
| SSH | `ssh-ed25519` | — |

```
info = "bip39-pm/v1/secret" || u32be(len(kind)) || kind || u32be(len(label)) || label || u32be(counter)
k_secret = HKDF-SHA256(salt = "bip39-pm/v1", ikm = k_app, info, L = 32)
stream = HKDF-Expand-SHA256(prk = k_secret, info = "bip39-pm/v1/stream", L = 1024)
```

- PIN: `n` раз `DIGITS[uniform(10)]`.
- Слова: `n` раз слово BIP39 с номером `((b0 << 8) | b1) & 0x7ff` из двух следующих байт, через пробел.
- Wi‑Fi: кодирование раздела 6 с политикой `len=<n>;cls=lud`.
- SSH: `k_secret` — seed ключа Ed25519 (RFC 8032), комментарий — метка; файл OpenSSH
  без шифрования, checkint выводится из ключа.

Векторы (мнемоника `abandon ×11 about`, счётчик 1): PIN 4 «карта» — `5987`; PIN 6
«карта сбер» — `936802`; 4 слова «secret question» — `rice trade budget staff`;
Wi‑Fi 20 «home wifi» — `1w2hnpKJyh93chs4N61a`; SSH «github laptop» — открытый ключ
`ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJv18B347hIuVqi6ZQ6S6DHpx082zNUl7P3W8NcYfnQT`.

## 11. Тестовые векторы

Мнемоника `abandon ×11 about`, passphrase пустая. Отпечаток: `era-primary-finish`.

| Домен | Логин | Счётчик | Политика | Пароль | Проверка |
| --- | --- | --- | --- | --- | --- |
| github.com | vlad@mail.ru | 1 | len=20;cls=luds | `q~9Tlw:qOyeSzu?69AUx` | amused-liquid |
| github.com | vlad@mail.ru | 2 | len=20;cls=luds | `eITvMChQRH+*gVT-n4FJ` | marble-clarify |
| github.com | other@mail.ru | 1 | len=20;cls=luds | `l4nhKOQY$x$E85uidyw4` | consider-glow |
| bank.ru | vlad | 1 | len=16;cls=lud | `oh1fWuHJh2e3emF0` | change-want |
| xn--e1afmkfd.xn--p1ai | vlad | 1 | len=8;cls=d | `48777879` | topple-seminar |

Векторы проверяются двумя независимыми реализациями: Rust (`tests/vectors.rs`) и Python
на стандартной библиотеке (`reference/pm_ref.py`). Деривация BIP85 сверена с официальным
вектором BIP85 (случай 1).
