import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show AnyhowException;

import 'strings.dart';

/// Язык интерфейса. Тексты в коде написаны по-русски, переводы — в strings.dart.
enum AppLang {
  en('English'),
  el('Ελληνικά'),
  ru('Русский');

  final String title;
  const AppLang(this.title);

  /// Язык системы, если он поддерживается, иначе английский.
  static AppLang system() {
    final code = PlatformDispatcher.instance.locale.languageCode;
    return AppLang.values.firstWhere(
      (l) => l.name == code,
      orElse: () => AppLang.en,
    );
  }
}

/// Текущий язык; меняется через AppState.setLang, интерфейс при этом перестраивается.
AppLang appLang = AppLang.ru;

/// Перевод строки. `{0}`, `{1}` … заменяются на [args].
String tr(String ru, [List<Object?> args = const []]) {
  var s = switch (appLang) {
    AppLang.ru => ru,
    AppLang.en => en[ru] ?? ru,
    AppLang.el => el[ru] ?? ru,
  };
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}

/// Текст ошибки ядра для пользователя: без технических префиксов и на языке интерфейса.
String trError(Object e) {
  var m = e is AnyhowException ? e.message : '$e';
  for (final p in ['ошибка индекса: ', 'ключ Pro: ']) {
    if (m.startsWith(p)) m = m.substring(p.length);
  }
  if (appLang == AppLang.ru) return m;
  final table = appLang == AppLang.en ? _errorsEn : _errorsEl;
  final exact = table[m];
  if (exact != null) return exact;
  for (final MapEntry(key: prefix, value: t) in table.entries) {
    if (prefix.endsWith(': ') && m.startsWith(prefix)) {
      return '$t${trError(m.substring(prefix.length))}';
    }
  }
  final range = RegExp(r'^(.+?) (\d+) вне диапазона (\d+)\.\.=(\d+)$')
      .firstMatch(m);
  if (range != null) {
    final what = table[range[1]] ?? range[1]!;
    return appLang == AppLang.en
        ? '$what ${range[2]} is outside ${range[3]}–${range[4]}'
        : '$what ${range[2]} εκτός ορίων ${range[3]}–${range[4]}';
  }
  return m;
}

const _errorsEn = {
  'некорректная seed-фраза: ': 'invalid seed phrase: ',
  'ошибка деривации: ': 'derivation error: ',
  'некорректный домен: ': 'invalid domain: ',
  'некорректная политика: ': 'invalid rule: ',
  'ключ SSH: ': 'SSH key: ',
  'длина': 'length',
  'длина PIN': 'PIN length',
  'число слов': 'word count',
  'длина пароля Wi‑Fi': 'Wi‑Fi password length',
  'нужен хотя бы один класс символов':
      'at least one character class is required',
  'счётчик начинается с 1': 'the version starts at 1',
  'пустая метка': 'the label is empty',
  'пустая строка': 'the address is empty',
  'файл не является индексом': 'this is not a ManagerBIP index',
  'не удалось расшифровать: другая seed/passphrase или файл повреждён':
      'could not decrypt: a different seed/passphrase or the data is damaged',
  'это не код переноса ManagerBIP': 'this is not a ManagerBIP transfer code',
  'код переноса повреждён': 'the transfer code is damaged',
  'в ключе опечатка': 'there is a typo in the key',
  'ключ должен начинаться с MBIP': 'the key must start with MBIP',
  'ключ не подходит': 'the key is not valid',
  'ключ отозван': 'the key has been revoked',
  'неверная длина ключа': 'wrong key length',
  'неизвестная редакция': 'unknown edition',
  'неподдерживаемая версия ключа': 'unsupported key version',
  'повреждённая подпись': 'damaged signature',
};

const _errorsEl = {
  'некорректная seed-фраза: ': 'μη έγκυρη φράση seed: ',
  'ошибка деривации: ': 'σφάλμα παραγωγής: ',
  'некорректный домен: ': 'μη έγκυρος τομέας: ',
  'некорректная политика: ': 'μη έγκυρος κανόνας: ',
  'ключ SSH: ': 'κλειδί SSH: ',
  'длина': 'μήκος',
  'длина PIN': 'μήκος PIN',
  'число слов': 'αριθμός λέξεων',
  'длина пароля Wi‑Fi': 'μήκος κωδικού Wi‑Fi',
  'нужен хотя бы один класс символов':
      'χρειάζεται τουλάχιστον μία κατηγορία χαρακτήρων',
  'счётчик начинается с 1': 'η έκδοση ξεκινά από το 1',
  'пустая метка': 'η ετικέτα είναι κενή',
  'пустая строка': 'η διεύθυνση είναι κενή',
  'файл не является индексом': 'αυτό δεν είναι ευρετήριο ManagerBIP',
  'не удалось расшифровать: другая seed/passphrase или файл повреждён': 'η αποκρυπτογράφηση απέτυχε: άλλη φράση seed/passphrase ή κατεστραμμένα δεδομένα',
  'это не код переноса ManagerBIP':
      'αυτό δεν είναι κωδικός μεταφοράς ManagerBIP',
  'код переноса повреждён': 'ο κωδικός μεταφοράς είναι κατεστραμμένος',
  'в ключе опечатка': 'υπάρχει λάθος στο κλειδί',
  'ключ должен начинаться с MBIP': 'το κλειδί πρέπει να ξεκινά με MBIP',
  'ключ не подходит': 'το κλειδί δεν είναι έγκυρο',
  'ключ отозван': 'το κλειδί έχει ανακληθεί',
  'неверная длина ключа': 'λάθος μήκος κλειδιού',
  'неизвестная редакция': 'άγνωστη έκδοση προϊόντος',
  'неподдерживаемая версия ключа': 'μη υποστηριζόμενη έκδοση κλειδιού',
  'повреждённая подпись': 'κατεστραμμένη υπογραφή',
};
