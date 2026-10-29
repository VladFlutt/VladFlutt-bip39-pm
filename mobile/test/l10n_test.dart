import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/l10n/strings.dart';
import 'package:mobile/src/l10n/tr.dart';

void main() {
  test('у каждой строки tr() есть перевод на английский и греческий', () {
    final literal = RegExp(r"\btr\(\s*'((?:[^'\\]|\\.)*)'");
    final missing = <String>[];
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.contains('/rust/')) continue;
      for (final m in literal.allMatches(f.readAsStringSync())) {
        final key = m[1]!.replaceAll(r"\'", "'").replaceAll(r'\$', r'$');
        for (final (name, map) in [('en', en), ('el', el)]) {
          if (!map.containsKey(key)) missing.add('$name: $key (${f.path})');
        }
      }
    }
    expect(missing, isEmpty);
  });

  test('плейсхолдеры совпадают с русским текстом', () {
    final ph = RegExp(r'\{\d\}');
    Set<String> of(String s) => ph.allMatches(s).map((m) => m[0]!).toSet();
    for (final map in [en, el]) {
      for (final MapEntry(:key, :value) in map.entries) {
        expect(of(value), of(key), reason: key);
      }
    }
  });

  test('tr подставляет аргументы на выбранном языке', () {
    addTearDown(() => appLang = AppLang.ru);
    appLang = AppLang.en;
    expect(tr('Шаг {0} из {1}', [2, 7]), 'Step 2 of 7');
    appLang = AppLang.el;
    expect(tr('Шаг {0} из {1}', [2, 7]), 'Βήμα 2 από 7');
    appLang = AppLang.ru;
    expect(tr('Шаг {0} из {1}', [2, 7]), 'Шаг 2 из 7');
  });

  test('ошибки ядра переводятся и теряют технический префикс', () {
    addTearDown(() => appLang = AppLang.ru);
    expect(trError('ключ Pro: ключ отозван'), 'ключ отозван');
    appLang = AppLang.en;
    expect(trError('ключ Pro: ключ отозван'), 'the key has been revoked');
    expect(
      trError('некорректная политика: длина 4 вне диапазона 8..=64'),
      'invalid rule: length 4 is outside 8–64',
    );
    expect(trError('что-то новое'), 'что-то новое');
    appLang = AppLang.el;
    expect(
      trError('ошибка индекса: это не код переноса ManagerBIP'),
      'αυτό δεν είναι κωδικός μεταφοράς ManagerBIP',
    );
  });
}
