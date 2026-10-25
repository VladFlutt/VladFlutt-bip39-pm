/// Длинный код переноса не помещается в один QR, поэтому он режется на кадры
/// `PMQ1:<номер>/<всего>:<часть>`, которые показываются по очереди.
const _prefix = 'PMQ1:';

/// Символов кода в одном кадре: QR остаётся крупным и читается с экрана.
const frameChunk = 600;

List<String> splitFrames(String text, {int chunk = frameChunk}) {
  final parts = <String>[
    for (var i = 0; i < text.length; i += chunk)
      text.substring(i, i + chunk > text.length ? text.length : i + chunk),
  ];
  return [
    for (var i = 0; i < parts.length; i++)
      '$_prefix${i + 1}/${parts.length}:${parts[i]}',
  ];
}

/// Собирает кадры в любом порядке, повторы игнорируются.
class FrameCollector {
  final _parts = <int, String>{};
  int? _total;

  int get received => _parts.length;
  int? get total => _total;
  bool get done => _total != null && _parts.length == _total;

  /// `false` — это не кадр ManagerBIP или кадр другого кода.
  bool add(String frame) {
    final m = RegExp(
      r'^PMQ1:(\d+)/(\d+):(.*)$',
      dotAll: true,
    ).firstMatch(frame);
    if (m == null) return false;
    final i = int.parse(m[1]!), n = int.parse(m[2]!);
    if (n < 1 || i < 1 || i > n) return false;
    if (_total != null && _total != n) return false;
    _total = n;
    _parts[i] = m[3]!;
    return true;
  }

  String get text => [for (var i = 1; i <= _total!; i++) _parts[i]!].join();
}
