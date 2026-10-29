# Публикация в Google Play

Идентификатор приложения: **`ai.metalogia.managerbip`**. После первой загрузки он не меняется.

## 1. Аккаунт разработчика

- Play Console: <https://play.google.com/console>. Разовый взнос $25.
- Личному аккаунту, созданному после ноября 2023 года, Google открывает публикацию
  в «Рабочей версии» только после закрытого теста: **не меньше 12 тестировщиков
  в течение 14 дней подряд**. Аккаунту организации (нужен D‑U‑N‑S) это не нужно.
- Нужна верификация личности. Из РФ регистрация и выплаты сейчас затруднены:
  аккаунт и платёжный профиль обычно оформляют на ИП или компанию в другой стране.

## 2. Ключ загрузки и секреты GitHub

Ключ загрузки (upload key) лежит в файлах проекта, в `play-signing/`. В репозиторий
он не попадает. Им подписываются сборки для Play Console. Ключ подписи приложения
Google хранит сам (Play App Signing), поэтому потерянный ключ загрузки можно
заменить через поддержку.

В GitHub: **Settings → Secrets and variables → Actions → New repository secret**.
Значения лежат в `play-signing/github-secrets.txt`:

| Секрет | Значение |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | всё содержимое `upload-keystore.base64.txt` |
| `ANDROID_KEYSTORE_PASSWORD` | пароль из `github-secrets.txt` |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | пароль из `github-secrets.txt` |

Когда секреты заданы, каждый push в `main` собирает подписанный AAB (задача `play`
в `.github/workflows/mobile.yml`). Файл появляется в пререлизе **android-play**.
Номер сборки растёт автоматически.

Локально: создайте `mobile/android/key.properties` (он в `.gitignore`)

```properties
storeFile=/полный/путь/upload-keystore.jks
storePassword=…
keyAlias=upload
keyPassword=…
```

и соберите `flutter build appbundle --release --dart-define=STORE=play`.

## 3. Play-сборка

`--dart-define=STORE=play` убирает из экрана Pro раздел «Купить ключ». Правила
Google Play запрещают уводить пользователя к оплате цифровых функций в обход
Play Billing. Ввод ключа остаётся.

## 4. Карточка приложения

**Политика конфиденциальности:** <https://bip39-pm.vercel.app/privacy.html>

**Категория:** Инструменты (Tools). **Контакт:** hello@metalogia.ai.

### Русский

- Название (до 30): `ManagerBIP — пароли из фразы`
- Краткое описание (до 80): `Все пароли из одной seed-фразы. Без сервера, без облака, без хранилища паролей.`
- Полное описание:

```
ManagerBIP не хранит пароли — он вычисляет их. Одна seed-фраза BIP39 из 12 или 24 слов даёт надёжный пароль для каждого сайта, на любом устройстве.

• Нечего украсть. Паролей нет ни на телефоне, ни на сервере: каждый пароль вычисляется заново из фразы, адреса сайта и логина.
• Потеряли телефон? Установите ManagerBIP заново, введите ту же фразу, и все пароли вернутся.
• Работает без интернета. Приложению не нужны сеть, аккаунт и облако.
• Вход по отпечатку, Face ID или коду устройства. Скриншоты запрещены, скопированный пароль стирается из буфера через 30 секунд.
• Свои правила для сайтов, которые не принимают символы или длинные пароли. Смена пароля одной кнопкой.
• Отпечаток фразы из трёх слов: сразу видно, что фраза введена верно.
• Режим обучения: попробуйте всё на тестовой фразе, ничего не сохраняется.
• Открытый стандарт и открытый код: те же пароли дают веб-версия, расширение для браузера и консольная утилита.

ManagerBIP Pro, разовая покупка:
• PIN-коды, кодовые слова, пароли Wi‑Fi и ключи SSH из той же фразы
• Перенос списка на другой телефон по QR и резервная копия
• Несколько профилей и скрытый профиль
• Шаблоны правил и правило для новых сайтов

Важно: не используйте фразу от криптокошелька с деньгами. Заведите для паролей отдельную.
```

### English

- Title: `ManagerBIP: seed passwords`
- Short description: `Every password from one seed phrase. No server, no cloud, no password vault.`
- Full description:

```
ManagerBIP doesn’t store passwords — it calculates them. One BIP39 seed phrase of 12 or 24 words gives a strong password for every site, on any device.

• Nothing to steal. There are no passwords on the phone or on a server: each one is derived again from the phrase, the site address and the login.
• Lost your phone? Install ManagerBIP again, enter the same phrase, and every password comes back.
• Works offline. No network, no account, no cloud.
• Unlock with fingerprint, Face ID or the device passcode. Screenshots are blocked, and a copied password is wiped from the clipboard after 30 seconds.
• Custom rules for sites that reject symbols or long passwords. Change a password with one tap.
• A three-word fingerprint of your phrase shows at once that it was entered correctly.
• Learning mode: try everything on a test phrase, nothing is saved.
• Open standard and open source: the web app, the browser extension and the command-line tool give the same passwords.

ManagerBIP Pro, one-time purchase:
• PIN codes, code words, Wi‑Fi passwords and SSH keys from the same phrase
• Move the list to another phone by QR, and backups
• Multiple profiles and a hidden profile
• Rule templates and a rule for new sites

Important: don’t use the phrase of a crypto wallet that holds money. Create a separate one for passwords.
```

### Ελληνικά

- Τίτλος: `ManagerBIP: κωδικοί από φράση`
- Σύντομη περιγραφή: `Όλοι οι κωδικοί από μία φράση seed. Χωρίς διακομιστή, χωρίς cloud.`
- Πλήρης περιγραφή:

```
Το ManagerBIP δεν αποθηκεύει κωδικούς — τους υπολογίζει. Μία φράση seed BIP39 με 12 ή 24 λέξεις δίνει ισχυρό κωδικό για κάθε ιστότοπο, σε κάθε συσκευή.

• Τίποτα για κλοπή. Δεν υπάρχουν κωδικοί ούτε στο τηλέφωνο ούτε σε διακομιστή: κάθε κωδικός υπολογίζεται ξανά από τη φράση, τη διεύθυνση του ιστότοπου και το όνομα χρήστη.
• Χάσατε το τηλέφωνο; Εγκαταστήστε ξανά το ManagerBIP, εισαγάγετε την ίδια φράση και όλοι οι κωδικοί επιστρέφουν.
• Λειτουργεί χωρίς internet. Χωρίς δίκτυο, λογαριασμό και cloud.
• Ξεκλείδωμα με δακτυλικό αποτύπωμα, Face ID ή κωδικό συσκευής. Τα στιγμιότυπα οθόνης απαγορεύονται και ο αντιγραμμένος κωδικός διαγράφεται από το πρόχειρο μετά από 30 δευτερόλεπτα.
• Δικοί σας κανόνες για ιστότοπους που δεν δέχονται σύμβολα ή μεγάλους κωδικούς. Αλλαγή κωδικού με ένα πάτημα.
• Αποτύπωμα τριών λέξεων: βλέπετε αμέσως ότι η φράση εισήχθη σωστά.
• Λειτουργία εκμάθησης: δοκιμάστε τα πάντα σε δοκιμαστική φράση, τίποτα δεν αποθηκεύεται.
• Ανοιχτό πρότυπο και ανοιχτός κώδικας: η web εφαρμογή, η επέκταση προγράμματος περιήγησης και το εργαλείο γραμμής εντολών δίνουν τους ίδιους κωδικούς.

ManagerBIP Pro, εφάπαξ αγορά:
• Κωδικοί PIN, κωδικές λέξεις, κωδικοί Wi‑Fi και κλειδιά SSH από την ίδια φράση
• Μεταφορά της λίστας σε άλλο τηλέφωνο με QR και αντίγραφα ασφαλείας
• Πολλά προφίλ και κρυφό προφίλ
• Πρότυπα κανόνων και κανόνας για νέους ιστότοπους

Σημαντικό: μη χρησιμοποιείτε τη φράση πορτοφολιού κρυπτονομισμάτων με χρήματα. Φτιάξτε ξεχωριστή για τους κωδικούς.
```

### Графика

- Значок 512×512: `mobile/assets/icon/play_store_512.png`.
- Графический баннер 1024×500 и от 2 до 8 скриншотов телефона (16:9 или 9:16, от 320 px).
  Скриншоты удобно снять в режиме обучения: там тестовая фраза и не видно настоящих паролей.

## 5. Анкеты Play Console

**Безопасность данных (Data safety):**
- Собирает ли приложение данные или передаёт их третьим лицам? **Нет.**
- Шифруются ли данные при передаче? Неприменимо: приложение ничего не передаёт.
- Можно ли запросить удаление данных? Данные хранятся только на устройстве и удаляются вместе с приложением.

**Доступ к приложению (App access):** все функции доступны без входа. Для проверки
можно указать «Режим обучения»: он открывает всё, включая Pro.

**Реклама:** нет. **Целевая аудитория:** 18+ (не для детей).
**Возрастной рейтинг (IARC):** утилита, ответы «нет» на все вопросы о контенте.
**Разрешения:** камера (сканирование QR переноса), биометрия (вход).
**Финансовые функции, здоровье, новости, VPN:** нет.

## 6. Порядок выпуска

1. Задать секреты GitHub (раздел 2), дождаться сборки на `main`, скачать AAB из пререлиза **android-play**.
2. Play Console → Создать приложение → заполнить карточку (раздел 4) и анкеты (раздел 5).
3. Тестирование → Закрытое тестирование → новый выпуск → загрузить AAB.
   При первой загрузке согласиться на Play App Signing.
4. Добавить не меньше 12 тестировщиков (Google-аккаунты или группа Google Groups) и держать тест 14 дней.
5. Запросить доступ к рабочей версии и выпустить.
