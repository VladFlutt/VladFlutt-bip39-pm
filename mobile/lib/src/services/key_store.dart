import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Где лежит `k_app` между запусками. Seed-фраза на устройстве не хранится.
abstract class KeyStore {
  Future<List<int>?> read();
  Future<void> write(List<int> key);
  Future<void> clear();
}

/// iOS Keychain (только это устройство, после первой разблокировки) /
/// Android Keystore через flutter_secure_storage.
class SecureKeyStore implements KeyStore {
  static const _name = 'k_app';
  final FlutterSecureStorage _storage;

  SecureKeyStore()
    : _storage = const FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
          synchronizable: false,
        ),
      );

  @override
  Future<List<int>?> read() async {
    final v = await _storage.read(key: _name);
    return v == null ? null : base64Decode(v);
  }

  @override
  Future<void> write(List<int> key) =>
      _storage.write(key: _name, value: base64Encode(key));

  @override
  Future<void> clear() => _storage.delete(key: _name);
}

/// Для учебного режима и тестов: ничего не переживает перезапуск.
class MemoryKeyStore implements KeyStore {
  List<int>? _key;

  @override
  Future<List<int>?> read() async => _key;

  @override
  Future<void> write(List<int> key) async => _key = List.of(key);

  @override
  Future<void> clear() async => _key = null;
}
