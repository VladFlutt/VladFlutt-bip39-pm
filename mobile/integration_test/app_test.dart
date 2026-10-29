import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/src/app.dart';
import 'package:mobile/src/l10n/tr.dart';
import 'package:mobile/src/rust/frb_generated.dart';
import 'package:mobile/src/services/biometric.dart';
import 'package:mobile/src/services/index_store.dart';
import 'package:mobile/src/services/key_store.dart';
import 'package:mobile/src/services/lang_store.dart';
import 'package:mobile/src/services/license_store.dart';
import 'package:mobile/src/state/app_state.dart';

import 'pro_cases.dart';

/// Полный путь через настоящее Rust-ядро: учебная фраза → онбординг →
/// пароль github.com должен совпасть с вектором из SPEC.md.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());

  AppState memoryState() {
    final keys = MemoryKeyStore();
    final index = MemoryIndexStore();
    return AppState(
      keyStoreFor: (_) => keys,
      indexStoreFor: (_) => index,
      biometric: NoBiometric(),
      licenseStore: MemoryLicenseStore(),
    );
  }

  Future<void> next(WidgetTester t) async {
    await t.tap(find.byKey(const Key('next')));
    await t.pumpAndSettle();
  }

  testWidgets('учебный режим: восстановление и пароль по вектору SPEC', (
    t,
  ) async {
    final state = memoryState();
    await t.pumpWidget(ManagerBipApp(state: state));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('mode-learning')));
    await t.pumpAndSettle();
    expect(find.textContaining('Учебный режим'), findsOneWidget);

    await next(t); // приветствие
    await t.tap(find.byKey(const Key('path-restore')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('use-demo')));
    await t.pumpAndSettle();
    await next(t); // выбор
    await next(t); // ввод фразы
    await next(t); // passphrase пустая
    expect(find.text('era-primary-finish'), findsOneWidget);
    await next(t); // отпечаток
    await next(t); // защита → готово
    expect(state.phase, Phase.unlocked);

    await t.tap(find.byKey(const Key('add')));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const Key('site')),
      'https://www.GitHub.com/login',
    );
    await t.enterText(find.byKey(const Key('login')), 'vlad@mail.ru');
    await t.pumpAndSettle();
    expect(find.textContaining('amused-liquid'), findsOneWidget);
    await t.tap(find.byTooltip('Показать'));
    await t.pumpAndSettle();
    expect(find.text('q~9Tlw:qOyeSzu?69AUx'), findsOneWidget);

    await t.tap(find.byKey(const Key('rotate')));
    await t.pumpAndSettle();
    expect(find.text('eITvMChQRH+*gVT-n4FJ'), findsOneWidget);
    expect(state.accounts.single.counter, 2);
  });

  testWidgets(
    'язык: выбор на первом экране и в настройках, выбор запоминается',
    (t) async {
      addTearDown(() => appLang = AppLang.ru);
      final langs = MemoryLangStore();
      final state = AppState(
        keyStoreFor: (_) => MemoryKeyStore(),
        indexStoreFor: (_) => MemoryIndexStore(),
        biometric: NoBiometric(),
        licenseStore: MemoryLicenseStore(),
        langStore: langs,
      );
      await t.pumpWidget(ManagerBipApp(state: state));
      await t.pumpAndSettle();
      expect(find.text('Обычный режим'), findsOneWidget);

      Future<void> pick(String lang) async {
        await t.tap(find.byKey(const Key('language')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(Key('lang-$lang')).last);
        await t.pumpAndSettle();
      }

      await pick('en');
      expect(find.text('Normal mode'), findsOneWidget);
      expect(await langs.read(), 'en');
      await pick('el');
      expect(find.text('Κανονική λειτουργία'), findsOneWidget);

      // В настройках: экран остаётся открытым и сразу показывает новый язык.
      await t.tap(find.byKey(const Key('mode-learning')));
      await t.pumpAndSettle();
      await next(t);
      await t.tap(find.byKey(const Key('path-restore')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('use-demo')));
      await t.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await next(t);
      }
      expect(state.phase, Phase.unlocked);
      await t.tap(find.byTooltip('Ρυθμίσεις'));
      await t.pumpAndSettle();
      await pick('en');
      expect(find.text('Settings'), findsOneWidget);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(find.text('Sites'), findsOneWidget);
      await t.tap(find.byTooltip('Settings'));
      await t.pumpAndSettle();
      await pick('ru');
      expect(find.text('Настройки'), findsOneWidget);

      // Новый запуск берёт сохранённый язык.
      await langs.write('el');
      await state.loadLang();
      expect(appLang, AppLang.el);
    },
  );

  testWidgets('обычный режим: новая фраза из 24 слов с проверкой', (t) async {
    final state = memoryState();
    await t.pumpWidget(ManagerBipApp(state: state));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('mode-normal')));
    await t.pumpAndSettle();
    await next(t);
    await t.tap(find.byKey(const Key('words-24')));
    await t.pumpAndSettle();
    await next(t); // «создать» выбрано по умолчанию

    expect(find.byKey(const Key('word-23')), findsOneWidget);
    expect(find.byKey(const Key('word-24')), findsNothing);
    final words = <String>[
      for (var i = 0; i < 24; i++)
        (t.widget<Text>(find.byKey(Key('word-$i'))).data!).split(' ').last,
    ];
    await t.tap(find.byKey(const Key('written')));
    await t.pumpAndSettle();
    await next(t);

    for (var i = 0; i < 24; i++) {
      final field = find.byKey(Key('verify-$i'));
      if (field.evaluate().isNotEmpty) await t.enterText(field, words[i]);
    }
    await t.pumpAndSettle();
    await next(t); // проверка
    await next(t); // passphrase
    final fp = t.widget<Text>(find.byKey(const Key('fingerprint'))).data!;
    expect(fp.split('-'), hasLength(3));
    await next(t);
    await next(t);
    expect(state.phase, Phase.unlocked);
    expect(state.fingerprint, fp);

    // Блокировка и разблокировка по сохранённому ключу.
    state.lock();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('unlock')));
    await t.pumpAndSettle();
    expect(state.phase, Phase.unlocked);
    expect(state.fingerprint, fp);
  });

  testWidgets('экран Pro: чужой ключ не активируется', (t) async {
    final state = memoryState();
    await t.pumpWidget(ManagerBipApp(state: state));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('mode-learning')));
    await t.pumpAndSettle();
    await next(t);
    await t.tap(find.byKey(const Key('path-restore')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('use-demo')));
    await t.pumpAndSettle();
    await next(t); // выбор
    expect(find.textContaining('Слов: 12'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await next(t);
    }
    expect(state.phase, Phase.unlocked);

    await t.tap(find.byTooltip('Настройки'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('open-pro')));
    await t.pumpAndSettle();
    expect(find.text('Бесплатная версия'), findsOneWidget);

    final activate = find.byKey(const Key('pro-activate'));
    await t.scrollUntilVisible(
      activate,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.enterText(find.byKey(const Key('pro-key')), 'MBIP-AEAQ-AAAD-5AAS');
    await t.pumpAndSettle();
    await t.tap(activate);
    await t.pumpAndSettle();
    expect(find.text('в ключе опечатка'), findsOneWidget);
    expect(state.isPro, isFalse);
    expect(await state.licenseStore.read(), isNull);
  });

  group('Pro', proCases);
}
