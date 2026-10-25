import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Где лежат `k_app` профилей и их список между запусками. Seed-фраза на устройстве
/// не хранится. Ключ основного профиля (`main`) лежит под прежним именем `k_app`.
abstract class KeyStore {
  Future<List<int>?> read(String profile);
  Future<void> write(String profile, List<int> key);
  Future<void> clear(String profile);

  /// Служебные записи: список профилей, закрытые кодом скрытые профили.
  Future<String?> readMeta(String name);
  Future<void> writeMeta(String name, String? value);
}

String keyName(String profile) =>
    profile == 'main' ? 'k_app' : 'k_app.$profile';

/// iOS Keychain (только это устройство, после первой разблокировки) /
/// Android Keystore через flutter_secure_storage.
class SecureKeyStore implements KeyStore {
  final FlutterSecureStorage _storage;

  SecureKeyStore()
    : _storage = const FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
          synchronizable: false,
        ),
      );

  @override
  Future<List<int>?> read(String profile) async {
    final v = await _storage.read(key: keyName(profile));
    return v == null ? null : base64Decode(v);
  }

  @override
  Future<void> write(String profile, List<int> key) =>
      _storage.write(key: keyName(profile), value: base64Encode(key));

  @override
  Future<void> clear(String profile) => _storage.delete(key: keyName(profile));

  @override
  Future<String?> readMeta(String name) => _storage.read(key: 'meta.$name');

  @override
  Future<void> writeMeta(String name, String? value) => value == null
      ? _storage.delete(key: 'meta.$name')
      : _storage.write(key: 'meta.$name', value: value);
}

/// Для учебного режима и тестов: ничего не переживает перезапуск.
class MemoryKeyStore implements KeyStore {
  final _keys = <String, List<int>>{};
  final _meta = <String, String>{};

  @override
  Future<List<int>?> read(String profile) async => _keys[profile];

  @override
  Future<void> write(String profile, List<int> key) async =>
      _keys[profile] = List.of(key);

  @override
  Future<void> clear(String profile) async => _keys.remove(profile);

  @override
  Future<String?> readMeta(String name) async => _meta[name];

  @override
  Future<void> writeMeta(String name, String? value) async =>
      value == null ? _meta.remove(name) : _meta[name] = value;
}
