import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Где лежит ключ Pro. Один на устройство, общий для обоих режимов.
abstract class LicenseStore {
  Future<String?> read();
  Future<void> write(String key);
  Future<void> clear();
}

class SecureLicenseStore implements LicenseStore {
  static const _name = 'pro_key';
  final FlutterSecureStorage _storage;

  SecureLicenseStore()
    : _storage = const FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
          synchronizable: false,
        ),
      );

  @override
  Future<String?> read() => _storage.read(key: _name);

  @override
  Future<void> write(String key) => _storage.write(key: _name, value: key);

  @override
  Future<void> clear() => _storage.delete(key: _name);
}

/// Для тестов: ничего не переживает перезапуск.
class MemoryLicenseStore implements LicenseStore {
  String? _key;

  @override
  Future<String?> read() async => _key;

  @override
  Future<void> write(String key) async => _key = key;

  @override
  Future<void> clear() async => _key = null;
}
