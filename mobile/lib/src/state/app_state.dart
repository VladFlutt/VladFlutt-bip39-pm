import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../config.dart';
import '../rust/api/license.dart';
import '../rust/api/pm.dart';
import '../services/billing.dart';
import '../services/biometric.dart';
import '../services/index_store.dart';
import '../services/key_store.dart';
import '../services/lang_store.dart';
import '../services/license_store.dart';
import '../l10n/tr.dart';

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

/// Профиль: своя фраза или passphrase, свой ключ и свой список сайтов.
/// Скрытый профиль не виден в списке и открывается только кодом.
class Profile {
  final String id;
  final String name;
  final bool hidden;

  const Profile(this.id, this.name, {this.hidden = false});

  static const main = Profile('main', 'Основной');

  /// Имя для показа: у основного профиля — на языке интерфейса.
  String get title => id == main.id && name == main.name ? tr(name) : name;

  Map<String, String> toJson() => {'id': id, 'name': name};

  static Profile fromJson(Map<String, dynamic> j, {bool hidden = false}) =>
      Profile(j['id'] as String, j['name'] as String, hidden: hidden);
}

const _emptyIndex = IndexData(accounts: [], secrets: [], templates: []);

class AppState extends ChangeNotifier {
  final KeyStore Function(AppMode) keyStoreFor;
  final IndexStore Function(AppMode) indexStoreFor;
  final Biometric biometric;
  final LicenseStore licenseStore;
  final LangStore langStore;
  final ProBilling billing;

  AppState({
    required this.keyStoreFor,
    required this.indexStoreFor,
    required this.biometric,
    required this.licenseStore,
    LangStore? langStore,
    ProBilling? billing,
  }) : langStore = langStore ?? MemoryLangStore(),
       billing = billing ?? NoBilling() {
    this.billing.addListener(notifyListeners);
  }

  /// Хранилища по умолчанию: настоящие для обычного режима, в памяти — для учебного.
  factory AppState.device() {
    final learnKeys = MemoryKeyStore();
    final learnIndex = MemoryIndexStore();
    return AppState(
      keyStoreFor: (m) => m == AppMode.normal ? SecureKeyStore() : learnKeys,
      indexStoreFor: (m) => m == AppMode.normal ? FileIndexStore() : learnIndex,
      biometric: DeviceBiometric(),
      licenseStore: SecureLicenseStore(),
      langStore: SecureLangStore(),
      billing: store == 'play' ? PlayBilling() : NoBilling(),
    );
  }

  /// Язык из настроек; без выбора — язык системы.
  Future<void> loadLang() async {
    final saved = await langStore.read();
    appLang = AppLang.values.asNameMap()[saved] ?? AppLang.system();
    notifyListeners();
  }

  Future<void> setLang(AppLang lang) async {
    appLang = lang;
    await langStore.write(lang.name);
    notifyListeners();
  }

  Phase phase = Phase.chooseMode;
  AppMode mode = AppMode.normal;
  Vault? _vault;
  IndexData index = _emptyIndex;
  String? error;

  /// Видимые профили; основной всегда первый.
  List<Profile> profiles = [Profile.main];
  Profile profile = Profile.main;

  /// Закрытая кодом запись открытого скрытого профиля (для удаления и показа).
  String? _hiddenBlob;

  /// Активированный ключ Pro, `null` — бесплатная версия.
  ProLicense? pro;

  bool get learning => mode == AppMode.learning;
  bool get isPro => pro != null || billing.owned;

  /// Pro-функции доступны с ключом и бесплатно в учебном режиме — для пробы.
  bool get proActive => isPro || learning;
  Vault get vault => _vault!;
  String get fingerprint => _vault?.fingerprint() ?? '';
  List<Account> get accounts => index.accounts;
  List<SecretItem> get secrets => index.secrets;
  List<RuleTemplate> get templates => index.templates;

  /// Правило для новых сайтов.
  PasswordPolicy get newSitePolicy =>
      index.defaultPolicy ?? PasswordPolicy.defaultPolicy();

  KeyStore get _keys => keyStoreFor(mode);
  IndexStore get _index => indexStoreFor(mode);

  /// Проверяет сохранённый ключ Pro и покупку в магазине при запуске.
  /// Отозванный ключ снимается.
  Future<void> loadPro() async {
    try {
      await billing.init();
    } catch (_) {
      // Без магазина остаётся ключ.
    }
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

  Future<void> chooseMode(AppMode m) async {
    mode = m;
    phase = Phase.loading;
    notifyListeners();
    await _loadProfiles();
    final stored = await _keys.read(Profile.main.id);
    phase = stored == null ? Phase.onboarding : Phase.locked;
    notifyListeners();
  }

  void backToModeChoice() {
    _close();
    phase = Phase.chooseMode;
    notifyListeners();
  }

  /// Проверяет фразу и passphrase, не сохраняя их. Возвращает хранилище для
  /// показа отпечатка на последнем шаге онбординга.
  Future<Vault> previewVault(String phrase, String passphrase) =>
      Vault.unlock(phrase: phrase, passphrase: passphrase);

  /// Завершает онбординг: `k_app` уходит в защищённое хранилище.
  Future<void> completeOnboarding(Vault v) async {
    await _keys.write(Profile.main.id, v.keyBytes());
    profiles = [Profile.main];
    await _saveProfiles();
    await _open(Profile.main, v);
  }

  /// Разблокировка всегда открывает основной профиль: скрытый — только кодом.
  Future<bool> unlock() async {
    if (!await biometric.authenticate(tr('Откройте ManagerBIP'))) return false;
    final key = await _keys.read(Profile.main.id);
    if (key == null) {
      phase = Phase.onboarding;
      notifyListeners();
      return false;
    }
    await _open(Profile.main, Vault.fromKey(key: key));
    return true;
  }

  void lock() {
    _close();
    phase = Phase.locked;
    notifyListeners();
  }

  /// Удаляет ключи, списки и профили с устройства. Пароли восстановятся из seed-фразы.
  Future<void> forgetDevice() async {
    for (final p in profiles) {
      await _keys.clear(p.id);
      await _index.clear(p.id);
    }
    if (profile.hidden) await _index.clear(profile.id);
    await _keys.writeMeta('profiles', null);
    await _keys.writeMeta('hidden', null);
    profiles = [Profile.main];
    _close();
    phase = Phase.onboarding;
    notifyListeners();
  }

  // ---- Профили ----

  Future<void> switchProfile(Profile p) async {
    final key = await _keys.read(p.id);
    if (key == null) {
      error = tr('Ключ профиля «{0}» не найден', [p.title]);
      notifyListeners();
      return;
    }
    await _open(p, Vault.fromKey(key: key));
  }

  /// Новый профиль из другой фразы или той же фразы с другой passphrase.
  Future<void> addProfile(String name, Vault v) async {
    final p = Profile(
      _newId(),
      name.trim().isEmpty ? tr('Профиль') : name.trim(),
    );
    await _keys.write(p.id, v.keyBytes());
    profiles = [...profiles, p];
    await _saveProfiles();
    await _open(p, v);
  }

  Future<void> renameProfile(Profile p, String name) async {
    final renamed = Profile(p.id, name.trim(), hidden: p.hidden);
    if (p.hidden) {
      await _rewrapHidden(renamed);
    } else {
      profiles = [for (final x in profiles) x.id == p.id ? renamed : x];
      await _saveProfiles();
    }
    if (profile.id == p.id) profile = renamed;
    notifyListeners();
  }

  /// Удаляет профиль с устройства (не основной). Пароли остаются в его фразе.
  Future<void> deleteProfile(Profile p) async {
    if (p.id == Profile.main.id) return;
    await _index.clear(p.id);
    if (p.hidden) {
      await _removeHiddenBlob();
    } else {
      await _keys.clear(p.id);
      profiles = profiles.where((x) => x.id != p.id).toList();
      await _saveProfiles();
    }
    if (profile.id == p.id) await switchProfile(Profile.main);
    notifyListeners();
  }

  /// Прячет открытый профиль: он исчезает из списка, ключ закрывается кодом.
  Future<void> hideProfile(String code) async {
    final p = profile;
    if (p.id == Profile.main.id || p.hidden) return;
    final hidden = Profile(p.id, p.name, hidden: true);
    _hiddenBlob = null;
    await _rewrapHidden(hidden, code: code);
    await _keys.clear(p.id);
    profiles = profiles.where((x) => x.id != p.id).toList();
    await _saveProfiles();
    profile = hidden;
    notifyListeners();
  }

  /// Возвращает открытый скрытый профиль в общий список.
  Future<void> unhideProfile() async {
    final p = profile;
    if (!p.hidden) return;
    await _keys.write(p.id, vault.keyBytes());
    await _removeHiddenBlob();
    profile = Profile(p.id, p.name);
    profiles = [...profiles, profile];
    await _saveProfiles();
    notifyListeners();
  }

  /// Открывает скрытый профиль по коду. `false` — такого кода нет.
  Future<bool> openHidden(String code) async {
    for (final blob in await _hiddenBlobs()) {
      try {
        final raw = await unwrapSecret(blob: base64Decode(blob), code: code);
        final j = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
        final p = Profile.fromJson(j, hidden: true);
        await _open(p, Vault.fromKey(key: base64Decode(j['key'] as String)));
        _hiddenBlob = blob;
        _hiddenCode = code;
        return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  String? _hiddenCode;

  Future<List<String>> _hiddenBlobs() async {
    final raw = await _keys.readMeta('hidden');
    return raw == null ? [] : (jsonDecode(raw) as List).cast<String>();
  }

  /// Записывает (или перезаписывает) закрытую кодом запись скрытого профиля.
  Future<void> _rewrapHidden(Profile p, {String? code}) async {
    final c = code ?? _hiddenCode!;
    final payload = utf8.encode(
      jsonEncode({...p.toJson(), 'key': base64Encode(vault.keyBytes())}),
    );
    final blob = base64Encode(await wrapSecret(secret: payload, code: c));
    final blobs = (await _hiddenBlobs()).where((b) => b != _hiddenBlob).toList()
      ..add(blob);
    await _keys.writeMeta('hidden', jsonEncode(blobs));
    _hiddenBlob = blob;
    _hiddenCode = c;
  }

  Future<void> _removeHiddenBlob() async {
    final blobs = (await _hiddenBlobs()).where((b) => b != _hiddenBlob);
    await _keys.writeMeta('hidden', jsonEncode(blobs.toList()));
    _hiddenBlob = null;
    _hiddenCode = null;
  }

  Future<void> _loadProfiles() async {
    final raw = await _keys.readMeta('profiles');
    final list = raw == null
        ? <Profile>[]
        : [
            for (final j in jsonDecode(raw) as List)
              Profile.fromJson(j as Map<String, dynamic>),
          ];
    profiles = [Profile.main, ...list.where((p) => p.id != Profile.main.id)];
  }

  Future<void> _saveProfiles() => _keys.writeMeta(
    'profiles',
    jsonEncode([for (final p in profiles) p.toJson()]),
  );

  String _newId() {
    final r = math.Random.secure();
    return [
      for (var i = 0; i < 8; i++)
        r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  Future<void> _open(Profile p, Vault v) async {
    _vault = v;
    profile = p;
    _hiddenBlob = null;
    _hiddenCode = null;
    await _loadIndex();
    phase = Phase.unlocked;
    notifyListeners();
  }

  void _close() {
    _vault = null;
    index = _emptyIndex;
    profile = Profile.main;
    _hiddenBlob = null;
    _hiddenCode = null;
  }

  // ---- Индекс ----

  Future<void> _loadIndex() async {
    final data = await _index.read(profile.id);
    try {
      index = data == null ? _emptyIndex : vault.decryptIndex(data: data);
      error = null;
    } catch (e) {
      index = _emptyIndex;
      error = tr('Индекс не открылся: {0}', [trError(e)]);
    }
  }

  Future<void> _persist(IndexData next) async {
    index = next;
    await _index.write(profile.id, vault.encryptIndex(data: next));
    notifyListeners();
  }

  IndexData _with({
    List<Account>? accounts,
    List<SecretItem>? secrets,
    List<RuleTemplate>? templates,
    PasswordPolicy? defaultPolicy,
    bool clearDefault = false,
  }) => IndexData(
    accounts: accounts ?? index.accounts,
    secrets: secrets ?? index.secrets,
    templates: templates ?? index.templates,
    defaultPolicy: clearDefault ? null : defaultPolicy ?? index.defaultPolicy,
  );

  Account? find(String domain, String login) {
    for (final a in accounts) {
      if (a.domain == domain && a.login == login) return a;
    }
    return null;
  }

  Future<void> save(Account account) => _persist(
    _with(
      accounts:
          [
            for (final a in accounts)
              if (a.domain != account.domain || a.login != account.login) a,
            account,
          ]..sort(
            (a, b) =>
                '${a.domain} ${a.login}'.compareTo('${b.domain} ${b.login}'),
          ),
    ),
  );

  Future<void> remove(Account account) =>
      _persist(_with(accounts: accounts.where((a) => a != account).toList()));

  SecretItem? findSecret(SecretType kind, String label) {
    for (final s in secrets) {
      if (s.kind == kind && s.label == label) return s;
    }
    return null;
  }

  Future<void> saveSecret(SecretItem item) => _persist(
    _with(
      secrets: [
        for (final s in secrets)
          if (s.kind != item.kind || s.label != item.label) s,
        item,
      ]..sort((a, b) => a.label.compareTo(b.label)),
    ),
  );

  Future<void> removeSecret(SecretItem item) =>
      _persist(_with(secrets: secrets.where((s) => s != item).toList()));

  Future<void> saveTemplate(RuleTemplate t) => _persist(
    _with(
      templates: [
        for (final x in templates)
          if (x.name != t.name) x,
        t,
      ],
    ),
  );

  Future<void> removeTemplate(RuleTemplate t) =>
      _persist(_with(templates: templates.where((x) => x != t).toList()));

  /// `null` — вернуть правило по умолчанию из спецификации.
  Future<void> setDefaultPolicy(PasswordPolicy? p) =>
      _persist(_with(defaultPolicy: p, clearDefault: p == null));

  /// Код переноса текущего профиля.
  String exportCode() => vault.exportText(data: index);

  /// Вливает код переноса в текущий профиль.
  Future<MergeResult> importCode(String text) async {
    final incoming = vault.importText(text: text);
    final r = mergeIndex(local: index, incoming: incoming);
    await _persist(r.data);
    return r;
  }
}
