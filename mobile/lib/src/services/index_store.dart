import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Зашифрованные индексы профилей (формат `PMIX`, тот же, что у CLI `pm`).
/// Основной профиль (`main`) — прежний файл `index.pmx`.
abstract class IndexStore {
  Future<List<int>?> read(String profile);
  Future<void> write(String profile, List<int> data);
  Future<void> clear(String profile);
}

class FileIndexStore implements IndexStore {
  Future<File> _file(String profile) async {
    final dir = await getApplicationSupportDirectory();
    final name = profile == 'main' ? 'index.pmx' : 'index.$profile.pmx';
    return File('${dir.path}/$name');
  }

  @override
  Future<List<int>?> read(String profile) async {
    final f = await _file(profile);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> write(String profile, List<int> data) async {
    final f = await _file(profile);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(data, flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> clear(String profile) async {
    final f = await _file(profile);
    if (await f.exists()) await f.delete();
  }
}

class MemoryIndexStore implements IndexStore {
  final _data = <String, List<int>>{};

  @override
  Future<List<int>?> read(String profile) async => _data[profile];

  @override
  Future<void> write(String profile, List<int> data) async =>
      _data[profile] = List.of(data);

  @override
  Future<void> clear(String profile) async => _data.remove(profile);
}
