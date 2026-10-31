# Публикация в RuStore

Идентификатор приложения тот же, что в Google Play: **`ai.metalogia.managerbip`**.

## Сборка

Каждый push в `main` собирает подписанный релизный APK (задача `play` в
`.github/workflows/mobile.yml`, те же секреты, что для Google Play). Файл лежит в
пререлизе **android-rustore**:
<https://github.com/VladFlutt/VladFlutt-bip39-pm/releases/download/android-rustore/ManagerBIP-rustore.apk>.

Сборка `--dart-define=STORE=rustore` не продаёт Pro через Google Play: на экране Pro
показываются ссылки на покупку ключа (сайт, Ozon, Wildberries) и поле для ключа.

APK подписан ключом загрузки из `play-signing/`. В RuStore подпись APK — это подпись
приложения: каждое обновление должно быть подписано тем же ключом, поэтому ключ
нельзя терять. Отладочный APK из пререлиза `android-debug` в RuStore не подходит.

## Консоль RuStore

1. <https://console.rustore.ru>: войдите через VK ID и зарегистрируйтесь как
   разработчик (физлицо, самозанятый, ИП или компания). Регистрация бесплатная.
2. «Приложения» → «Создать приложение», загрузите `ManagerBIP-rustore.apk`.
3. Карточка: название, краткое и полное описание (русский текст из
   `docs/play-store.md`), значок 512×512, скриншоты из
   `integration_test/store/screenshots.dart`, категория «Инструменты».
4. Политика конфиденциальности: <https://bip39-pm.vercel.app/privacy.html>.
5. Возрастной рейтинг: 12+ или выше, контента для взрослых нет.
6. Отправьте на модерацию. Проверка обычно занимает несколько рабочих дней.

Если модерация попросит продавать Pro через платежи RuStore, в приложение
добавляется RuStore Billing SDK так же, как добавлен Google Play Billing
(`lib/src/services/billing.dart`).
