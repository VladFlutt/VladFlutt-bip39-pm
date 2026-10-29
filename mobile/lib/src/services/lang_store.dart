import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Выбранный язык интерфейса: `en`, `el`, `ru` или ничего (язык системы).
abstract class LangStore {
  Future<String?> read();
  Future<void> write(String lang);
}

class SecureLangStore implements LangStore {
  static const _name = 'lang';
  final _storage = const FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _name);

  @override
  Future<void> write(String lang) => _storage.write(key: _name, value: lang);
}

/// Для тестов: ничего не переживает перезапуск.
class MemoryLangStore implements LangStore {
  String? _lang;

  @override
  Future<String?> read() async => _lang;

  @override
  Future<void> write(String lang) async => _lang = lang;
}
