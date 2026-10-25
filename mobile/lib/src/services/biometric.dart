import 'package:local_auth/local_auth.dart';

/// Подтверждение владельца перед открытием хранилища.
abstract class Biometric {
  Future<bool> available();
  Future<bool> authenticate(String reason);
}

class DeviceBiometric implements Biometric {
  final _auth = LocalAuthentication();

  @override
  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      // Без biometricOnly: если отпечаток не распознан, можно ввести код устройства.
      return await _auth.authenticate(localizedReason: reason);
    } catch (_) {
      return false;
    }
  }
}

/// Устройство без биометрии и тесты: подтверждение не требуется.
class NoBiometric implements Biometric {
  @override
  Future<bool> available() async => false;

  @override
  Future<bool> authenticate(String reason) async => true;
}
