import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../rust/api/pm.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../ui/hint.dart';
import '../l10n/tr.dart';

enum _Path { create, restore }

enum _Step {
  welcome,
  choose,
  showPhrase,
  verify,
  enterPhrase,
  passphrase,
  fingerprint,
  protect,
}

/// Пошаговая настройка: новая фраза или восстановление, passphrase, отпечаток, защита.
class OnboardingScreen extends StatefulWidget {
  /// Задан — экран добавляет профиль: без приветствия и шага защиты, результат уходит сюда.
  final Future<void> Function(Vault)? onProfile;

  const OnboardingScreen({super.key, this.onProfile});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _index = 0;
  _Path _path = _Path.create;
  int _words = 12;
  String _phrase = '';
  bool _written = false;
  List<int> _verifyPositions = [];
  final Map<int, TextEditingController> _verify = {};
  final _restore = TextEditingController();
  final _pass1 = TextEditingController();
  final _pass2 = TextEditingController();
  Vault? _vault;
  String? _error;
  bool _busy = false;
  late final List<String> _wordlist = bip39Wordlist();
  late final List<int> _wordCounts = seedWordCounts();
  late final List<int> _newWordCounts = newSeedWordCounts();

  int get _restoreCount {
    final t = _restore.text.trim();
    return t.isEmpty ? 0 : t.split(RegExp(r'\s+')).length;
  }

  bool get _adding => widget.onProfile != null;

  List<_Step> get _steps => [
    if (!_adding) _Step.welcome,
    _Step.choose,
    if (_path == _Path.create) ...[
      _Step.showPhrase,
      _Step.verify,
    ] else
      _Step.enterPhrase,
    _Step.passphrase,
    _Step.fingerprint,
    if (!_adding) _Step.protect,
  ];

  bool get _last => _index == _steps.length - 1;

  _Step get _step => _steps[_index];

  @override
  void dispose() {
    for (final c in [_restore, _pass1, _pass2, ..._verify.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _newPhrase() {
    _phrase = generateMnemonic(words: _words);
    _written = false;
    final positions = List.generate(_words, (i) => i)
      ..shuffle(math.Random.secure());
    _verifyPositions = positions.take(3).toList()..sort();
    for (final c in _verify.values) {
      c.dispose();
    }
    _verify
      ..clear()
      ..addEntries(
        _verifyPositions.map((p) => MapEntry(p, TextEditingController())),
      );
  }

  bool get _canNext => switch (_step) {
    _Step.showPhrase => _written,
    _Step.verify => _verifyPositions.every(
      (p) => _verify[p]!.text.trim().toLowerCase() == _phrase.split(' ')[p],
    ),
    _Step.enterPhrase => _wordCounts.contains(_restoreCount),
    _Step.passphrase => _pass1.text == _pass2.text,
    _ => !_busy,
  };

  Future<void> _next() async {
    setState(() => _error = null);
    final state = AppScope.of(context);
    if (_step == _Step.choose && _path == _Path.create) {
      _newPhrase();
    }
    if (_step == _Step.passphrase) {
      setState(() => _busy = true);
      try {
        final phrase = _path == _Path.create ? _phrase : _restore.text;
        _vault = await state.previewVault(phrase, _pass1.text);
      } catch (e) {
        setState(() {
          _busy = false;
          _error = _path == _Path.restore
              ? tr(
                  'Фраза не прошла проверку: опечатка в слове или неверный порядок. ({0})',
                  [trError(e)],
                )
              : trError(e);
        });
        return;
      }
      setState(() => _busy = false);
    }
    if (_last) {
      if (_adding) {
        await widget.onProfile!(_vault!);
        if (mounted) Navigator.of(context).pop();
      } else {
        await state.completeOnboarding(_vault!);
      }
      return;
    }
    setState(() => _index++);
  }

  void _back() {
    if (_index == 0) {
      if (_adding) {
        Navigator.of(context).pop();
      } else {
        AppScope.of(context).backToModeChoice();
      }
    } else {
      setState(() {
        _error = null;
        _index--;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: tr('Назад'),
          onPressed: _back,
        ),
        title: Text(tr('Шаг {0} из {1}', [_index + 1, steps.length])),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: (_index + 1) / steps.length),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: ListView(
                      key: ValueKey(_step),
                      padding: const EdgeInsets.all(20),
                      children: _body(context),
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('next'),
                      onPressed: _canNext ? _next : null,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_last ? tr('Готово') : tr('Далее')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget title(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(s, style: text.headlineSmall),
    );
    final learning = AppScope.of(context).learning;
    switch (_step) {
      case _Step.welcome:
        return [
          title(tr('Добро пожаловать в ManagerBIP')),
          Text(
            tr(
              'ManagerBIP не хранит пароли. Он каждый раз вычисляет их из вашей seed-фразы, адреса сайта и логина. Одна фраза — пароли для всех сайтов, на любом устройстве.',
            ),
          ),
          Hint(
            short: tr(
              'Потеряли телефон? Установите ManagerBIP заново, введите ту же фразу, и все пароли вернутся.',
            ),
            learn: tr(
              'Seed-фраза BIP39 — это от 12 до 24 слов из словаря на 2048 слов. Из неё по стандарту BIP85 выводится отдельный ключ приложения, а из него через HKDF — пароль для каждого сайта. Утечка одного пароля не раскрывает ни фразу, ни другие пароли.',
            ),
          ),
        ];
      case _Step.choose:
        return [
          title(
            _adding ? tr('Фраза нового профиля') : tr('У вас уже есть фраза?'),
          ),
          RadioGroup<_Path>(
            groupValue: _path,
            onChanged: (v) => setState(() => _path = v!),
            child: Column(
              children: [
                RadioListTile(
                  key: Key('path-create'),
                  value: _Path.create,
                  title: Text(tr('Создать новую фразу')),
                  subtitle: Text(tr('Первый запуск ManagerBIP')),
                ),
                RadioListTile(
                  key: Key('path-restore'),
                  value: _Path.restore,
                  title: Text(tr('Восстановить по фразе')),
                  subtitle: Text(tr('Новый телефон или переустановка')),
                ),
              ],
            ),
          ),
          if (_path == _Path.create) ...[
            const SizedBox(height: 8),
            Text(tr('Сколько слов во фразе')),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              key: const Key('word-count'),
              showSelectedIcon: false,
              segments: [
                for (final n in _newWordCounts)
                  ButtonSegment(
                    value: n,
                    label: Text(
                      n % 10 == 4 ? tr('{0} слова', [n]) : tr('{0} слов', [n]),
                      key: Key('words-$n'),
                    ),
                  ),
              ],
              selected: {_words},
              onSelectionChanged: (s) => setState(() => _words = s.first),
            ),
          ],
          if (learning && _path == _Path.restore)
            OutlinedButton.icon(
              key: const Key('use-demo'),
              icon: const Icon(Icons.auto_fix_high),
              label: Text(tr('Подставить учебную фразу')),
              onPressed: () => setState(() => _restore.text = demoMnemonic),
            ),
          if (_adding)
            Hint(
              short: tr(
                'Та же фраза с другой passphrase — тоже отдельный профиль: выберите «Восстановить», введите свою фразу и новую passphrase.',
              ),
            ),
          Hint(
            short: tr(
              'Не используйте фразу от криптокошелька с деньгами. Заведите для паролей отдельную.',
            ),
            learn: tr(
              '12 слов дают 128 бит стойкости — этого достаточно. 24 слова — 256 бит, с запасом. Восстановить можно и фразу из 15, 18 или 21 слова от другого приложения.',
            ),
          ),
        ];
      case _Step.showPhrase:
        final words = _phrase.split(' ');
        return [
          title(tr('Запишите фразу на бумагу')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < words.length; i++)
                    Chip(
                      label: Text('${i + 1}. ${words[i]}', key: Key('word-$i')),
                    ),
                ],
              ),
            ),
          ),
          CheckboxListTile(
            key: const Key('written'),
            value: _written,
            onChanged: (v) => setState(() => _written = v ?? false),
            title: Text(tr('Фраза записана на бумагу')),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          Hint(
            short: tr(
              'Не фотографируйте фразу и не храните её в заметках или облаке.',
            ),
            learn: tr(
              'Кто знает фразу, знает все ваши пароли. ManagerBIP не сохраняет фразу на телефоне, поэтому бумажная копия — единственный способ восстановить доступ.',
            ),
          ),
        ];
      case _Step.verify:
        return [
          title(tr('Проверим запись')),
          Text(tr('Введите слова с этими номерами.')),
          const SizedBox(height: 12),
          for (final p in _verifyPositions)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                key: Key('verify-$p'),
                controller: _verify[p],
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: tr('Слово №{0}', [p + 1]),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          Hint(
            learn: tr(
              'Так мы убеждаемся, что фраза записана без ошибок, пока её ещё видно на экране.',
            ),
          ),
        ];
      case _Step.enterPhrase:
        final current = _restore.text.endsWith(' ')
            ? ''
            : _restore.text.trim().split(RegExp(r'\s+')).last;
        final suggestions = current.isEmpty
            ? const <String>[]
            : _wordlist
                  .where(
                    (w) => w.startsWith(current.toLowerCase()) && w != current,
                  )
                  .take(6)
                  .toList();
        return [
          title(tr('Введите вашу фразу')),
          TextField(
            key: const Key('restore-phrase'),
            controller: _restore,
            minLines: 3,
            maxLines: 5,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: tr('слова через пробел'),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final w in suggestions)
                ActionChip(
                  label: Text(w),
                  onPressed: () => setState(() {
                    final parts = _restore.text.trim().split(RegExp(r'\s+'))
                      ..removeLast();
                    _restore.text = '${[...parts, w].join(' ')} ';
                    _restore.selection = TextSelection.collapsed(
                      offset: _restore.text.length,
                    );
                  }),
                ),
            ],
          ),
          Text(
            tr('Слов: {0} (бывает {1})', [
              _restoreCount,
              _wordCounts.join(', '),
            ]),
            key: const Key('restore-count'),
          ),
          Hint(
            short: tr('Порядок слов важен. Регистр и лишние пробелы не важны.'),
            learn: tr(
              'Последнее слово содержит контрольную сумму, поэтому опечатку ManagerBIP почти всегда заметит сам.',
            ),
          ),
        ];
      case _Step.passphrase:
        return [
          title(tr('Passphrase (необязательно)')),
          TextField(
            key: const Key('pass1'),
            controller: _pass1,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Passphrase',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('pass2'),
            controller: _pass2,
            obscureText: true,
            decoration: InputDecoration(
              labelText: tr('Повторите passphrase'),
              border: const OutlineInputBorder(),
              errorText: _pass1.text == _pass2.text ? null : tr('Не совпадает'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          Hint(
            short: tr(
              'Оставьте пустым, если не уверены. Без той же passphrase пароли будут другими.',
            ),
            learn: tr(
              'Passphrase — «25-е слово». С ней одна бумажная фраза даёт совсем другой набор паролей. Это защищает, если бумажку найдут, но passphrase тоже нельзя забыть.',
            ),
          ),
        ];
      case _Step.fingerprint:
        return [
          title(tr('Отпечаток вашей фразы')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _vault?.fingerprint() ?? '',
                key: const Key('fingerprint'),
                textAlign: TextAlign.center,
                style: text.headlineMedium,
              ),
            ),
          ),
          Hint(
            short: tr(
              'Запомните эти три слова. Их можно хранить где угодно: они не раскрывают фразу.',
            ),
            learn: tr(
              'При восстановлении на новом телефоне ManagerBIP покажет отпечаток снова. Если слова другие — значит, во фразе или passphrase ошибка, и пароли тоже будут другими.',
            ),
          ),
        ];
      case _Step.protect:
        return [
          title(tr('Защита на этом телефоне')),
          ListTile(
            leading: Icon(Icons.fingerprint),
            title: Text(tr('Вход по Face ID, отпечатку или коду устройства')),
          ),
          ListTile(
            leading: Icon(Icons.visibility_off_outlined),
            title: Text(tr('Скриншоты экрана запрещены')),
          ),
          ListTile(
            leading: Icon(Icons.timer_outlined),
            title: Text(
              tr('Скопированный пароль стирается из буфера через 30 секунд'),
            ),
          ),
          Hint(
            short: learning
                ? null
                : tr(
                    'Фраза не сохраняется на телефоне. В защищённом хранилище остаётся только ключ приложения.',
                  ),
            learn: tr(
              'В учебном режиме ключ живёт только в памяти и исчезнет, когда вы закроете приложение.',
            ),
          ),
        ];
    }
  }
}
