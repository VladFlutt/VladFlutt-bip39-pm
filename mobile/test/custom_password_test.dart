import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/l10n/tr.dart';
import 'package:mobile/src/rust/api/pm.dart';
import 'package:mobile/src/rust/frb_generated.dart';
import 'package:mobile/src/screens/site_screen.dart';
import 'package:mobile/src/services/billing.dart';
import 'package:mobile/src/services/biometric.dart';
import 'package:mobile/src/services/index_store.dart';
import 'package:mobile/src/services/key_store.dart';
import 'package:mobile/src/services/license_store.dart';
import 'package:mobile/src/state/app_scope.dart';
import 'package:mobile/src/state/app_state.dart';

class FailingIndexStore extends MemoryIndexStore {
  bool fail = false;
  @override
  Future<void> write(String profile, List<int> data) async {
    if (fail) throw StateError('disk full');
    await super.write(profile, data);
  }
}

class BlockingIndexStore extends MemoryIndexStore {
  final resume = Completer<void>();
  @override
  Future<void> write(String profile, List<int> data) async {
    await resume.future;
    await super.write(profile, data);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RustLib.init());
  setUp(() => appLang = AppLang.ru);

  Future<AppState> opened({
    AppMode mode = AppMode.normal,
    ProBilling? billing,
    IndexStore? store,
  }) async {
    final keys = MemoryKeyStore();
    final indexes = store ?? MemoryIndexStore();
    final state = AppState(
      keyStoreFor: (_) => keys,
      indexStoreFor: (_) => indexes,
      biometric: NoBiometric(),
      licenseStore: MemoryLicenseStore(),
      billing: billing,
    );
    await state.chooseMode(mode);
    await state.completeOnboarding(await state.previewVault(demoMnemonic, ''));
    return state;
  }

  Account account(String? password, {int counter = 1}) => Account(
    domain: 'example.com',
    login: 'user',
    counter: counter,
    policy: PasswordPolicy.defaultPolicy(),
    customPassword: password,
  );

  test('free: generated passwords work, custom creation is rejected', () async {
    final state = await opened();
    await state.save(account(null));
    await expectLater(state.save(account('custom')), throwsStateError);
    expect(state.accounts.single.customPassword, isNull);
  });

  test(
    'Pro: save, edit, reopen and transfer preserve the exact custom value',
    () async {
      final billing = FakeBilling();
      await billing.buy();
      final state = await opened(billing: billing);
      const password = '  My own 🔑 пароль  ';
      await state.save(account(password));
      state.lock();
      await state.unlock();
      expect(state.accounts.single.customPassword, password);
      await state.save(account('changed', counter: 2));
      final copy = await opened(mode: AppMode.learning);
      await copy.importCode(state.exportCode());
      expect(copy.accounts.single.customPassword, 'changed');
      state.billing.dispose();
      state.dispose();
    },
  );

  test(
    'stored custom passwords remain readable without Pro; edits are blocked',
    () async {
      final state = await opened(mode: AppMode.learning);
      await state.save(account('saved'));
      state.mode = AppMode.normal;
      state.lock();
      await state.unlock();
      expect(state.proActive, isFalse);
      expect(state.accounts.single.customPassword, 'saved');
      await expectLater(state.save(account('changed')), throwsStateError);
      expect(state.accounts.single.customPassword, 'saved');
    },
  );

  test('failed save keeps the prior in-memory and on-disk password', () async {
    final store = FailingIndexStore();
    final state = await opened(mode: AppMode.learning, store: store);
    await state.save(account('saved'));
    store.fail = true;
    await expectLater(state.save(account('changed')), throwsStateError);
    expect(state.accounts.single.customPassword, 'saved');
    state.lock();
    await state.unlock();
    expect(state.accounts.single.customPassword, 'saved');
  });

  test('locking during a save keeps decrypted custom passwords out of locked state', () async {
    final store = BlockingIndexStore();
    final state = await opened(mode: AppMode.learning, store: store);
    final saving = state.save(account('saved'));
    await Future<void>.delayed(Duration.zero);
    state.lock();
    store.resume.complete();
    await saving;
    expect(state.phase, Phase.locked);
    expect(state.accounts, isEmpty);
    await state.unlock();
    expect(state.accounts.single.customPassword, 'saved');
  });

  Future<void> showSite(
    WidgetTester t,
    AppState state, {
    Account? entry,
  }) async {
    await t.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(home: SiteScreen(account: entry)),
      ),
    );
    await t.pumpAndSettle();
    if (entry == null) {
      await t.enterText(find.byKey(const Key('site')), 'example.com');
      await t.enterText(find.byKey(const Key('login')), 'user');
      await t.pumpAndSettle();
    }
  }

  testWidgets('free custom switch opens Pro dialog', (t) async {
    final state = await t.runAsync(() => opened());
    await showSite(t, state!);
    await t.tap(find.byKey(const Key('custom-mode')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('pro-more')), findsOneWidget);
    expect(find.byKey(const Key('custom-password')), findsNothing);
  });

  testWidgets(
    'learning: empty custom value cannot save; custom value persists',
    (t) async {
      final state = await t.runAsync(() => opened(mode: AppMode.learning));
      await showSite(t, state!);
      await t.tap(find.byKey(const Key('custom-mode')));
      await t.pumpAndSettle();
      final save = find.byKey(const Key('save'));
      await t.scrollUntilVisible(
        save,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(t.widget<FilledButton>(save).onPressed, isNull);
      await t.scrollUntilVisible(
        find.byKey(const Key('custom-password')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.enterText(
        find.byKey(const Key('custom-password')),
        '  custom 🔑  ',
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        save,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(save);
      await t.pumpAndSettle();
      expect(state.accounts.single.customPassword, '  custom 🔑  ');
      expect(find.byKey(const Key('rotate')), findsNothing);
      await t.scrollUntilVisible(
        find.byKey(const Key('custom-mode')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.byKey(const Key('custom-mode')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        save,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(save);
      await t.pumpAndSettle();
      expect(state.accounts.single.customPassword, isNull);
      expect(state.accounts.single.counter, 2);
    },
  );
}
