import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/app.dart';
import 'package:mobile/src/rust/api/pm.dart';
import 'package:mobile/src/services/biometric.dart';
import 'package:mobile/src/services/index_store.dart';
import 'package:mobile/src/services/key_store.dart';
import 'package:mobile/src/services/license_store.dart';
import 'package:mobile/src/services/qr_frames.dart';
import 'package:mobile/src/state/app_state.dart';

/// Pro-функции через настоящее Rust-ядро. В учебном режиме Pro открыт для пробы.
/// Вызывается из `app_test.dart`: на Linux несколько файлов интеграционных тестов
/// подряд не запускаются, поэтому файл с тестами один.
void proCases() {
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

  Future<void> tap(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester t, String key) =>
      tap(t, find.byKey(Key(key)));

  /// Выбор режима → восстановление учебной фразой (с passphrase) → готово.
  Future<void> restoreDemo(
    WidgetTester t, {
    String passphrase = '',
    bool adding = false,
  }) async {
    if (!adding) await tapKey(t, 'next'); // приветствие
    await tapKey(t, 'path-restore');
    await tapKey(t, 'use-demo');
    await tapKey(t, 'next'); // выбор
    await tapKey(t, 'next'); // ввод фразы
    await t.enterText(find.byKey(const Key('pass1')), passphrase);
    await t.enterText(find.byKey(const Key('pass2')), passphrase);
    await t.pumpAndSettle();
    await tapKey(t, 'next'); // passphrase
    await tapKey(t, 'next'); // отпечаток
    if (!adding) await tapKey(t, 'next'); // защита
  }

  Future<AppState> startLearning(WidgetTester t) async {
    final state = memoryState();
    await t.pumpWidget(ManagerBipApp(state: state));
    await t.pumpAndSettle();
    await tapKey(t, 'mode-learning');
    await restoreDemo(t);
    expect(state.phase, Phase.unlocked);
    return state;
  }

  /// Ждёт асинхронную работу ядра (PBKDF2 и т. п.), которую pumpAndSettle не видит.
  Future<void> waitFor(WidgetTester t, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await t.pump();
    }
    await t.pumpAndSettle();
  }

  Future<void> answer(WidgetTester t, String text) async {
    await t.enterText(find.byKey(const Key('ask-text')), text);
    await tapKey(t, 'ask-ok');
  }

  test('кадры QR собираются в любом порядке', () {
    final code = 'PMX1:${'x' * 1500}';
    final frames = splitFrames(code);
    expect(frames, hasLength(3));
    final c = FrameCollector();
    expect(c.add('чужой QR'), isFalse);
    for (final f in [frames[2], frames[0], frames[2], frames[1]]) {
      expect(c.add(f), isTrue);
    }
    expect(c.done, isTrue);
    expect(c.text, code);
    expect(c.add(splitFrames('y' * 10).single), isFalse, reason: 'другой код');
  });

  testWidgets('без ключа Pro-функции предлагают купить Pro', (t) async {
    final state = memoryState();
    await t.pumpWidget(ManagerBipApp(state: state));
    await t.pumpAndSettle();
    await tapKey(t, 'mode-normal');
    await tapKey(t, 'next');
    await tapKey(t, 'next'); // создать
    await tapKey(t, 'written');
    // Проверку слов проходим через состояние: здесь важен только Pro.
    final v = await state.previewVault(demoMnemonic, '');
    await state.completeOnboarding(v);
    await t.pumpAndSettle();
    expect(state.proActive, isFalse);

    await tapKey(t, 'tab-secrets');
    await tapKey(t, 'add');
    expect(find.byKey(const Key('pro-more')), findsOneWidget);
    await tapKey(t, 'pro-more');
    expect(find.text('ManagerBIP Pro'), findsOneWidget);
  });

  testWidgets('секреты: PIN по вектору SPEC и ключ SSH', (t) async {
    final state = await startLearning(t);
    await tapKey(t, 'tab-secrets');
    await tapKey(t, 'add');
    await t.enterText(find.byKey(const Key('secret-label')), ' Карта ');
    await t.pumpAndSettle();
    await tap(t, find.byTooltip('Показать'));
    expect(find.text('5987'), findsOneWidget);
    await tapKey(t, 'secret-save');
    expect(state.secrets.single.label, 'карта');
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.text('карта'), findsOneWidget);

    await tapKey(t, 'add');
    await tapKey(t, 'kind-ssh');
    await t.enterText(find.byKey(const Key('secret-label')), 'github laptop');
    await t.pumpAndSettle();
    expect(
      t.widget<Text>(find.byKey(const Key('ssh-public'))).data,
      'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJv18B347hIuVqi6ZQ6S6DHpx082zNUl7P3W8NcYfnQT github laptop',
    );
    await tapKey(t, 'secret-save');
    expect(state.secrets, hasLength(2));
  });

  testWidgets('шаблоны и правило для новых сайтов', (t) async {
    final state = await startLearning(t);
    await tap(t, find.byTooltip('Настройки'));
    await tapKey(t, 'open-default-policy');
    await tapKey(t, 'template-Без символов');
    await tapKey(t, 'default-save');
    expect(state.newSitePolicy.symbols, isFalse);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();

    await tapKey(t, 'add');
    await t.enterText(find.byKey(const Key('site')), 'bank.ru');
    await t.enterText(find.byKey(const Key('login')), 'vlad');
    await t.pumpAndSettle();
    expect(find.textContaining('len=20;cls=lud'), findsOneWidget);

    await tap(t, find.text('Правила пароля'));
    await tapKey(t, 'template-add');
    await t.enterText(find.byKey(const Key('template-name')), 'Банк');
    await tapKey(t, 'template-save');
    expect(state.templates.single.name, 'Банк');
  });

  testWidgets('перенос: код с одного телефона вливается в другой', (t) async {
    // «Старый телефон»: та же учебная фраза, два сайта.
    final old = memoryState();
    await old.chooseMode(AppMode.learning);
    await old.completeOnboarding(await old.previewVault(demoMnemonic, ''));
    await old.save(
      Account(
        domain: 'github.com',
        login: 'vlad@mail.ru',
        counter: 3,
        policy: PasswordPolicy.defaultPolicy(),
      ),
    );
    await old.save(
      Account(
        domain: 'bank.ru',
        login: 'vlad',
        counter: 1,
        policy: PasswordPolicy.defaultPolicy(),
      ),
    );
    final code = old.exportCode();

    final state = await startLearning(t);
    await tap(t, find.byTooltip('Настройки'));
    await tapKey(t, 'open-transfer');
    await t.enterText(find.byKey(const Key('paste-code')), code);
    await t.pumpAndSettle();
    await tapKey(t, 'import-code');
    expect(find.textContaining('Добавлено: 2'), findsOneWidget);
    expect(state.find('github.com', 'vlad@mail.ru')!.counter, 3);

    // Код другой фразы не открывается.
    t
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .removeCurrentSnackBar();
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await tapKey(t, 'open-transfer');
    final other = memoryState();
    await other.chooseMode(AppMode.learning);
    await other.completeOnboarding(await other.previewVault(demoMnemonic, 'x'));
    await t.enterText(find.byKey(const Key('paste-code')), other.exportCode());
    await t.pumpAndSettle();
    await tapKey(t, 'import-code');
    expect(
      find.textContaining('другая seed/passphrase', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('профили: добавить, скрыть кодом, открыть после блокировки', (
    t,
  ) async {
    final state = await startLearning(t);
    final mainFp = state.fingerprint;
    await tap(t, find.byTooltip('Настройки'));
    await tapKey(t, 'open-profiles');
    await tapKey(t, 'add-profile');
    await answer(t, 'Рабочий');
    await restoreDemo(t, passphrase: 'work', adding: true);
    expect(state.profile.name, 'Рабочий');
    expect(state.fingerprint, isNot(mainFp));
    expect(state.profiles.map((p) => p.name), ['Основной', 'Рабочий']);

    await state.save(
      Account(
        domain: 'work.ru',
        login: 'me',
        counter: 1,
        policy: PasswordPolicy.defaultPolicy(),
      ),
    );
    await t.pumpAndSettle();
    await tapKey(t, 'hide-profile');
    await answer(t, '2468');
    await waitFor(t, () => state.profile.hidden);
    expect(state.profile.hidden, isTrue);
    expect(state.profiles.map((p) => p.name), ['Основной']);

    state.lock();
    await t.pumpAndSettle();
    await tapKey(t, 'unlock');
    expect(state.profile.id, Profile.main.id);
    expect(state.accounts, isEmpty);

    expect(await state.openHidden('1111'), isFalse);
    expect(await state.openHidden('2468'), isTrue);
    await t.pumpAndSettle();
    expect(state.profile.name, 'Рабочий');
    expect(state.accounts.single.domain, 'work.ru');

    await state.unhideProfile();
    expect(state.profiles.map((p) => p.name), ['Основной', 'Рабочий']);
    await state.switchProfile(Profile.main);
    await state.switchProfile(state.profiles.last);
    expect(state.accounts.single.domain, 'work.ru');
  });
}
