import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Покупка Pro в магазине приложений. Ключ Pro работает независимо от неё.
abstract class ProBilling extends ChangeNotifier {
  /// Сборка продаёт Pro через магазин.
  bool get available => true;

  /// Магазин подтвердил покупку (последнее известное состояние, переживает перезапуск).
  bool get owned;

  /// Цена из магазина; `null` — покупка в магазине недоступна.
  String? get price;

  /// Идёт покупка или восстановление.
  bool get busy;

  /// Текст последней ошибки покупки, `null` — ошибки нет.
  String? get error;

  Future<void> init();
  Future<void> buy();
  Future<void> restore();
}

/// Сборки не для Google Play: покупка только ключом.
class NoBilling extends ProBilling {
  @override
  bool get available => false;
  @override
  bool get owned => false;
  @override
  String? get price => null;
  @override
  bool get busy => false;
  @override
  String? get error => null;
  @override
  Future<void> init() async {}
  @override
  Future<void> buy() async {}
  @override
  Future<void> restore() async {}
}

/// Google Play Billing: разовая покупка `managerbip_pro`. Проверки на сервере нет:
/// приложение работает без сети, поэтому доверяет ответу Play на устройстве.
class PlayBilling extends ProBilling {
  static const productId = 'managerbip_pro';
  static const _cacheKey = 'pro_play';

  final _iap = InAppPurchase.instance;
  final _storage = const FlutterSecureStorage();
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _product;
  bool _owned = false;
  bool _busy = false;
  String? _error;

  @override
  bool get owned => _owned;
  @override
  String? get price => _product?.price;
  @override
  bool get busy => _busy;
  @override
  String? get error => _error;

  @override
  Future<void> init() async {
    _owned = await _storage.read(key: _cacheKey) == '1';
    notifyListeners();
    if (!await _iap.isAvailable()) return;
    _sub = _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => _fail(e.toString()),
    );
    final res = await _iap.queryProductDetails({productId});
    _product = res.productDetails.isEmpty ? null : res.productDetails.first;
    notifyListeners();
    // Покупка с другого телефона или после переустановки.
    if (!_owned) unawaited(_iap.restorePurchases().catchError((_) {}));
  }

  @override
  Future<void> buy() async {
    final p = _product;
    if (p == null || _busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final started = await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: p),
      );
      if (!started) _fail(null);
    } catch (e) {
      _fail(e.toString());
    }
  }

  @override
  Future<void> restore() async {
    if (_busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _iap.restorePurchases();
    } catch (e) {
      _fail(e.toString());
      return;
    }
    // Если покупок нет, Play ничего не присылает.
    _busy = false;
    notifyListeners();
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      if (p.productID != productId) continue;
      switch (p.status) {
        case PurchaseStatus.purchased || PurchaseStatus.restored:
          _owned = true;
          _busy = false;
          await _storage.write(key: _cacheKey, value: '1');
        case PurchaseStatus.error:
          _fail(p.error?.message);
        case PurchaseStatus.canceled:
          _fail(null);
        case PurchaseStatus.pending:
          break;
      }
      // Без подтверждения Play вернёт деньги через три дня.
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
    notifyListeners();
  }

  void _fail(String? message) {
    _busy = false;
    _error = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Для тестов: покупка проходит сразу.
class FakeBilling extends ProBilling {
  bool _owned = false;

  @override
  bool get owned => _owned;
  @override
  String? get price => '199 ₽';
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
