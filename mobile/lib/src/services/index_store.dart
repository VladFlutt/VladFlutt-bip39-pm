import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Зашифрованный индекс аккаунтов (формат `PMIX`, тот же, что у CLI `pm`).
abstract class IndexStore {
  Future<List<int>?> read();
  Future<void> write(List<int> data);
  Future<void> clear();
}

class FileIndexStore implements IndexStore {
  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/index.pmx');
  }

  @override
  Future<List<int>?> read() async {
    final f = await _file();
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> write(List<int> data) async {
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(data, flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> clear() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}

class MemoryIndexStore implements IndexStore {
  List<int>? _data;

  @override
  Future<List<int>?> read() async => _data;

  @override
  Future<void> write(List<int> data) async => _data = List.of(data);

  @override
  Future<void> clear() async => _data = null;
}
