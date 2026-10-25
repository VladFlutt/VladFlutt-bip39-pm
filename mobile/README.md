# ManagerBIP — мобильное приложение

Flutter-приложение для iOS и Android поверх Rust-ядра `bip39-pm`. Пароли вычисляет
тот же код, что и CLI `pm` (через [flutter_rust_bridge](https://cjycode.com/flutter_rust_bridge/)),
поэтому на телефоне и в терминале они совпадают побитно.

## Что умеет

- **Выбор режима при каждом запуске.** «Обычный» — ваша фраза, ключ в защищённом хранилище.
  «Обучение» — тестовая фраза из SPEC.md, подробные подсказки на каждом экране, ничего не сохраняется.
- **Пошаговый онбординг:** что это такое → создать или восстановить → запись фразы и проверка
  трёх слов (или ввод с подсказками из словаря BIP39) → passphrase → отпечаток → защита.
- **Список сайтов** (зашифрованный индекс `PMIX`, совместим с CLI), поиск, карточка сайта:
  пароль, проверочные слова, правила пароля, «Сменить» (версия + 1).
- **Длина новой фразы на выбор:** 12, 15, 18, 21 или 24 слова. Восстановление принимает любую из них.
- **ManagerBIP Pro** (Настройки → ManagerBIP Pro): статус, что даёт Pro, ссылки на магазины,
  ввод ключа `MBIP-…`. Ключ проверяется офлайн публичным ключом издателя
  (`rust/src/api/license.rs`) и хранится в Keychain/Keystore. Ссылки на Ozon, WB и сайт —
  в `lib/src/config.dart`, пустая ссылка скрывает кнопку.
- **Обои** с контурами символов криптовалют (рисуются кодом, `lib/src/ui/wallpaper.dart`).

## Безопасность

- Seed-фраза на устройстве **не хранится**. После онбординга в iOS Keychain / Android Keystore
  (`flutter_secure_storage`) записывается только `k_app` — ключ приложения BIP85. Из него
  выводятся пароли, но не ключи криптокошелька на той же фразе.
- Вход — Face ID, отпечаток или код устройства (`local_auth`). При уходе приложения в фон
  ключ выгружается из памяти.
- Android: `FLAG_SECURE` (нет скриншотов и превью в недавних), `allowBackup=false`.
- Скопированный пароль стирается из буфера через 30 секунд.

Что ещё не сделано: привязка ключа к биометрии на уровне Keystore/Secure Enclave
(сейчас биометрия проверяется в приложении), размытие экрана в переключателе приложений на iOS,
экспорт и импорт индекса, автозаполнение паролей (iOS AutoFill / Android Autofill Service).

## Устройство

```
mobile/
  rust/src/api/pm.rs      API для Dart: Vault, derive, индекс, словарь BIP39
  lib/src/rust/           сгенерированные привязки (не править руками)
  lib/src/state/          AppState: режим, фазы (выбор → онбординг → блокировка → список)
  lib/src/services/       Keychain/Keystore, биометрия, файл индекса
  lib/src/screens/        экраны
  integration_test/       сквозные тесты через настоящее Rust-ядро
```

## Сборка

Нужны Flutter 3.47+, Rust stable; для Android — Android SDK и NDK, для iOS — Xcode.
Rust-библиотеку собирает cargokit автоматически при `flutter run`/`flutter build`.

```sh
cd mobile
flutter run                      # на подключённом телефоне или эмуляторе
flutter build apk                # Android
flutter build ios --no-codesign  # iOS (на macOS)
```

После изменения `rust/src/api/` перегенерируйте привязки:

```sh
cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked
cargo install cargo-expand --locked
flutter_rust_bridge_codegen generate
```

## Тесты

```sh
(cd rust && cargo test)                               # векторы SPEC через API моста
flutter test integration_test -d linux                # сквозные сценарии (на Linux через xvfb-run)
```

Linux-таргет оставлен только для тестов и разработки без телефона.
