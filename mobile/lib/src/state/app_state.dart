import 'package:flutter/foundation.dart';

import '../services/biometric.dart';
import '../services/index_store.dart';
import '../rust/api/license.dart';
import '../rust/api/pm.dart';
import '../services/key_store.dart';
import '../services/license_store.dart';

/// Режим, который пользователь выбирает при запуске.
enum AppMode {
  /// Настоящая seed-фраза, ключ в Keychain/Keystore.
  normal,

  /// Учебная фраза из SPEC.md, подсказки на каждом экране, ничего не сохраняется.
  learning,
}

/// Учебная фраза: официальный тестовый вектор BIP39, ею нельзя пользоваться всерьёз.
const demoMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

enum Phase { chooseMode, loading, onboarding, locked, unlocked }

class AppState extends ChangeNotifier {
  final KeyStore Function(AppMode) keyStoreFor;
  final IndexStore Function(AppMode) indexStoreFor;
  final Biometric biometric;
  final LicenseStore licenseStore;

  AppState({
    required this.keyStoreFor,
    required this.indexStoreFor,
    required this.biometric,
    required this.licenseStore,
  });

  /// Хранилища по умолчанию: настоящие для обычного режима, в памяти — для учебного.
  factory AppState.device() {
    final learnKeys = MemoryKeyStore();
    final learnIndex = MemoryIndexStore();
    return AppState(
      keyStoreFor: (m) => m == AppMode.normal ? SecureKeyStore() : learnKeys,
      indexStoreFor: (m) => m == AppMode.normal ? FileIndexStore() : learnIndex,
      biometric: DeviceBiometric(),
      licenseStore: SecureLicenseStore(),
    );
  }

  Phase phase = Phase.chooseMode;
  AppMode mode = AppMode.normal;
  Vault? _vault;
  List<Account> accounts = [];
  String? error;

  /// Активированный ключ Pro, `null` — бесплатная версия.
  ProLicense? pro;

  bool get learning => mode == AppMode.learning;
  Vault get vault => _vault!;
  String get fingerprint => _vault?.fingerprint() ?? '';

  bool get isPro => pro != null;

  KeyStore get _keys => keyStoreFor(mode);
  IndexStore get _index => indexStoreFor(mode);

  Future<void> chooseMode(AppMode m) async {
    mode = m;
    phase = Phase.loading;
    notifyListeners();
    final stored = await _keys.read();
    phase = stored == null ? Phase.onboarding : Phase.locked;
    notifyListeners();
  }

  /// Проверяет сохранённый ключ Pro при запуске. Отозванный ключ снимается.
  Future<void> loadPro() async {
    final key = await licenseStore.read();
    if (key == null) return;
    try {
      pro = verifyProKey(key: key);
    } catch (_) {
      pro = null;
      await licenseStore.clear();
    }
    notifyListeners();
  }

  /// Активирует ключ Pro. Бросает исключение с текстом ошибки, если ключ не подошёл.
  Future<void> activatePro(String key) async {
    final lic = verifyProKey(key: key);
    await licenseStore.write(key.trim());
    pro = lic;
    notifyListeners();
  }

  void backToModeChoice() {
    _vault = null;
    accounts = [];
    phase = Phase.chooseMode;
    notifyListeners();
  }

  /// Проверяет фразу и passphrase, не сохраняя их. Возвращает хранилище для
  /// показа отпечатка на последнем шаге онбординга.
  Future<Vault> previewVault(String phrase, String passphrase) =>
      Vault.unlock(phrase: phrase, passphrase: passphrase);

  /// Завершает онбординг: `k_app` уходит в защищённое хранилище.
  Future<void> completeOnboarding(Vault v) async {
    await _keys.write(v.keyBytes());
    _vault = v;
    await _loadIndex();
    phase = Phase.unlocked;
    notifyListeners();
  }

  Future<bool> unlock() async {
    if (!await biometric.authenticate('Откройте ManagerBIP')) return false;
    final key = await _keys.read();
    if (key == null) {
      phase = Phase.onboarding;
      notifyListeners();
      return false;
    }
    _vault = Vault.fromKey(key: key);
    await _loadIndex();
    phase = Phase.unlocked;
    notifyListeners();
    return true;
  }

  void lock() {
    _vault = null;
    accounts = [];
    phase = Phase.locked;
    notifyListeners();
  }

  /// Удаляет ключ и индекс с устройства. Пароли восстановятся из seed-фразы.
  Future<void> forgetDevice() async {
    await _keys.clear();
    await _index.clear();
    _vault = null;
    accounts = [];
    phase = Phase.onboarding;
    notifyListeners();
  }

  Future<void> _loadIndex() async {
    final data = await _index.read();
    try {
      accounts = data == null ? [] : vault.decryptIndex(data: data);
      error = null;
    } catch (e) {
      accounts = [];
      error = 'Индекс не открылся: $e';
    }
  }

  Account? find(String domain, String login) {
    for (final a in accounts) {
      if (a.domain == domain && a.login == login) return a;
    }
    return null;
  }

  Future<void> save(Account account) async {
    accounts =
        [
          for (final a in accounts)
            if (a.domain != account.domain || a.login != account.login) a,
          account,
        ]..sort(
          (a, b) =>
              '${a.domain} ${a.login}'.compareTo('${b.domain} ${b.login}'),
        );
    await _index.write(vault.encryptIndex(accounts: accounts));
    notifyListeners();
  }

  Future<void> remove(Account account) async {
    accounts = accounts.where((a) => a != account).toList();
    await _index.write(vault.encryptIndex(accounts: accounts));
    notifyListeners();
  }
}
