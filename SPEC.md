# Спецификация bip39-pm v1

Статус: **заморожена**. Любое изменение алгоритма ниже меняет пароли пользователей,
поэтому допускается только новая версия (`v2`) рядом со старой, а не правка `v1`.

## 1. Seed

1. Мнемоника BIP39 (12 или 24 слова, английский словарь), контрольная сумма проверяется.
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
"note"?}]}`. Паролей в индексе нет. Без индекса восстанавливаются все пароли со
счётчиком 1 и политикой по умолчанию.

## 9. Тестовые векторы

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
