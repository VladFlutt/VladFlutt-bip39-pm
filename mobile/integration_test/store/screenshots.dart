import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/src/app.dart';
import 'package:mobile/src/l10n/tr.dart';
import 'package:mobile/src/rust/api/pm.dart';
import 'package:mobile/src/rust/frb_generated.dart';
import 'package:mobile/src/services/billing.dart';
import 'package:mobile/src/services/biometric.dart';
import 'package:mobile/src/services/index_store.dart';
import 'package:mobile/src/services/key_store.dart';
import 'package:mobile/src/services/license_store.dart';
import 'package:mobile/src/state/app_state.dart';

/// Скриншоты для карточки Google Play на учебной фразе:
/// `xvfb-run -a flutter test integration_test/store/screenshots.dart -d linux`.
/// PNG 1080×2160 складываются в `build/store_screenshots/<язык>/`.
/// В CI не запускается: это не проверка, а съёмка.
class _ShopBilling extends ProBilling {
  _ShopBilling(this._price);
  final String _price;
  bool _owned = false;

  @override
  bool get owned => _owned;
  @override
  String? get price => _price;
  @override
  bool get busy => false;
  @override
  String? get error => null;
  @override
  Future<void> init() async {}
  @override
  Future<void> buy() async {
    _owned = true;
    notifyListeners();
  }

  @override
  Future<void> restore() => buy();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());

  for (final (lang, price) in [
    (AppLang.ru, '299 ₽'),
    (AppLang.en, r'$3.99'),
    (AppLang.el, '3,99 €'),
  ]) {
    testWidgets('скриншоты ${lang.name}', (t) async {
      t.view.physicalSize = const Size(1080, 2160);
      t.view.devicePixelRatio = 2.75;
      addTearDown(t.view.reset);

      final keys = MemoryKeyStore();
      final index = MemoryIndexStore();
      final billing = _ShopBilling(price);
      final state = AppState(
        keyStoreFor: (_) => keys,
        indexStoreFor: (_) => index,
        biometric: NoBiometric(),
        licenseStore: MemoryLicenseStore(),
        billing: billing,
      );
      await state.setLang(lang);
      String l(String ru, String en, String el) =>
          {AppLang.ru: ru, AppLang.en: en, AppLang.el: el}[lang]!;
      final wifi = l('Домашний Wi‑Fi', 'Home Wi‑Fi', 'Wi‑Fi σπιτιού');
      final shot = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: shot,
          child: ManagerBipApp(state: state),
        ),
      );
      await t.pumpAndSettle();

      final dir = Directory('build/store_screenshots/${lang.name}')
        ..createSync(recursive: true);
      var n = 0;
      Future<void> snap(String name) async {
        await t.pumpAndSettle();
        final boundary =
            shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await t.runAsync(() async {
          final img = await boundary.toImage(pixelRatio: 2.75);
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          n++;
          File('${dir.path}/${n.toString().padLeft(2, '0')}-$name.png')
              .writeAsBytesSync(png!.buffer.asUint8List());
        });
      }

      Future<void> tap(Finder f) async {
        await t.ensureVisible(f);
        await t.pumpAndSettle();
        await t.tap(f);
        await t.pumpAndSettle();
      }

      // Обычный режим, без баннера учебного; фраза — учебная.
      await snap('mode');
      await tap(find.byKey(const Key('mode-normal')));
      final v = await state.previewVault(demoMnemonic, '');
      await state.completeOnboarding(v);
      await t.pumpAndSettle();
      final std = PasswordPolicy.defaultPolicy();
      for (final (domain, login, counter) in [
        ('github.com', 'alice', 1),
        ('google.com', 'alice@gmail.com', 1),
        ('bank.example', 'alice', 2),
        ('amazon.com', 'alice@gmail.com', 1),
        ('reddit.com', 'alice_r', 1),
        ('netflix.com', 'alice@gmail.com', 3),
      ]) {
        await state.save(
          Account(domain: domain, login: login, counter: counter, policy: std),
        );
      }
      await tap(find.byTooltip(tr('Настройки')));
      await tap(find.byKey(const Key('open-pro')));
      await snap('pro');
      await tap(find.byType(BackButton));
      await tap(find.byType(BackButton));
      await billing.buy();
      for (final (kind, size, label) in [
        (SecretType.wifi, 20, wifi),
        (SecretType.pin, 4, l('PIN карты', 'Card PIN', 'PIN κάρτας')),
        (
          SecretType.words,
          4,
          l('Кодовое слово банка', 'Bank code word', 'Κωδική λέξη τράπεζας'),
        ),
        (SecretType.ssh, 0, 'server-1'),
      ]) {
        await state.saveSecret(
          SecretItem(kind: kind, size: size, label: label, counter: 1),
        );
      }
      await t.pumpAndSettle();
      await snap('sites');

      await tap(find.text('github.com'));
      await tap(find.byIcon(Icons.visibility));
      await snap('site');
      await tap(find.byType(BackButton));

      await tap(find.byKey(const Key('tab-secrets')));
      await snap('secrets');
      await tap(find.text(wifi));
      await tap(find.byIcon(Icons.visibility));
      await snap('secret');
      await tap(find.byType(BackButton));
    });
  }
}
