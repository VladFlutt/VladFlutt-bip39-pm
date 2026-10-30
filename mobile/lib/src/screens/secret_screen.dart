import 'package:flutter/material.dart';

import '../rust/api/pm.dart';
import '../state/app_scope.dart';
import '../ui/clipboard.dart';
import '../ui/hint.dart';
import '../ui/wallpaper.dart';
import '../l10n/tr.dart';

Map<SecretType, String> get secretTypeNames => {
  SecretType.pin: 'PIN',
  SecretType.words: tr('Слова'),
  SecretType.wifi: 'Wi‑Fi',
  SecretType.ssh: 'SSH',
};

const secretTypeIcons = {
  SecretType.pin: Icons.pin_outlined,
  SecretType.words: Icons.record_voice_over_outlined,
  SecretType.wifi: Icons.wifi,
  SecretType.ssh: Icons.terminal,
};

/// Карточка секрета: значение вычисляется из фразы на лету.
class SecretScreen extends StatefulWidget {
  final SecretItem? item;

  const SecretScreen({super.key, this.item});

  @override
  State<SecretScreen> createState() => _SecretScreenState();
}

class _SecretScreenState extends State<SecretScreen> {
  late SecretType _kind = widget.item?.kind ?? SecretType.pin;
  late int _size = widget.item?.size ?? secretSizeBounds(kind: _kind)[2];
  late final _label = TextEditingController(text: widget.item?.label);
  late int _counter = widget.item?.counter ?? 1;
  bool _show = false;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  (SecretValue?, String?) _derive() {
    if (_label.text.trim().isEmpty) return (null, null);
    try {
      return (
        AppScope.of(context).vault.deriveSecret(
          kind: _kind,
          size: _size,
          label: _label.text,
          counter: _counter,
        ),
        null,
      );
    } catch (e) {
      return (null, trError(e));
    }
  }

  Future<void> _save(SecretValue v, {bool rotate = false}) async {
    final counter = rotate ? _counter + 1 : _counter;
    await AppScope.of(context).saveSecret(
      SecretItem(
        kind: _kind,
        size: _size,
        label: v.label,
        counter: counter,
        note: widget.item?.note,
      ),
    );
    setState(() => _counter = counter);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            rotate
                ? tr('Новое значение, версия {0}', [counter])
                : tr('Сохранено в списке'),
          ),
        ),
      );
    }
  }

  String get _hint => switch (_kind) {
    SecretType.pin => tr(
      'PIN для карты, домофона, сейфа или приложения банка.',
    ),
    SecretType.words => tr(
      'Кодовое слово для банка или ответ на секретный вопрос: настоящий ответ легко узнать, этот — нет.',
    ),
    SecretType.wifi => tr(
      'Пароль для роутера: только буквы и цифры, чтобы его было просто ввести на телевизоре.',
    ),
    SecretType.ssh => tr(
      'Ключ SSH Ed25519. Открытый ключ добавьте на сервер или в GitHub, закрытый — в ~/.ssh.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final (value, error) = _derive();
    final saved = value == null ? null : state.findSecret(_kind, value.label);
    final bounds = secretSizeBounds(kind: _kind);
    final scheme = Theme.of(context).colorScheme;
    final mono = const TextStyle(fontFamily: 'monospace', fontSize: 16);
    return CryptoWallpaper(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(widget.item?.label ?? tr('Новый секрет')),
          actions: [
            if (saved != null)
              IconButton(
                tooltip: tr('Убрать из списка'),
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await state.removeSecret(saved);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<SecretType>(
              key: const Key('secret-kind'),
              showSelectedIcon: false,
              segments: [
                for (final k in SecretType.values)
                  ButtonSegment(
                    value: k,
                    icon: Icon(secretTypeIcons[k]),
                    // Длинные названия (Words, Λέξεις) не переносятся, а уменьшаются.
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        secretTypeNames[k]!,
                        key: Key('kind-${k.name}'),
                        maxLines: 1,
                      ),
                    ),
                  ),
              ],
              selected: {_kind},
              onSelectionChanged: widget.item != null
                  ? null
                  : (s) => setState(() {
                      _kind = s.first;
                      _size = secretSizeBounds(kind: _kind)[2];
                      _show = false;
                    }),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('secret-label'),
              controller: _label,
              enabled: widget.item == null,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: tr('Для чего'),
                hintText: tr('карта сбер, домашний wifi, github laptop'),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            Hint(
              short: _hint,
              learn: tr(
                'Секрет вычисляется из фразы, метки и версии, как пароль сайта. Регистр и пробелы в метке не важны. Запомните метку: без неё секрет не восстановить.',
              ),
            ),
            if (_kind != SecretType.ssh)
              ListTile(
                title: Text(
                  _kind == SecretType.words
                      ? tr('Слов: {0}', [_size])
                      : tr('Длина: {0}', [_size]),
                ),
                subtitle: Slider(
                  key: const Key('secret-size'),
                  min: bounds[0].toDouble(),
                  max: bounds[1].toDouble(),
                  divisions: bounds[1] - bounds[0],
                  value: _size.toDouble(),
                  onChanged: (v) => setState(() => _size = v.round()),
                ),
              ),
            if (error != null)
              Text(error, style: TextStyle(color: scheme.error)),
            if (value != null) ...[
              if (value.public != null)
                Card(
                  child: ListTile(
                    title: Text(tr('Открытый ключ')),
                    subtitle: Text(
                      value.public!,
                      key: const Key('ssh-public'),
                      style: mono.copyWith(fontSize: 12),
                    ),
                    trailing: IconButton(
                      tooltip: tr('Копировать открытый ключ'),
                      icon: const Icon(Icons.copy),
                      onPressed: () => copyWithWipe(
                        context,
                        value.public!,
                        what: tr('Открытый ключ скопирован'),
                        ttl: null,
                      ),
                    ),
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (value.public != null)
                        Text(tr('Закрытый ключ — никому не показывайте')),
                      Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              _show
                                  ? value.value
                                  : '•' *
                                        (value.public != null
                                            ? 24
                                            : value.value.length),
                              key: const Key('secret-value'),
                              style: value.public != null
                                  ? mono.copyWith(fontSize: 10)
                                  : mono.copyWith(fontSize: 20),
                            ),
                          ),
                          IconButton(
                            tooltip: _show ? tr('Скрыть') : tr('Показать'),
                            icon: Icon(
                              _show ? Icons.visibility_off : Icons.visibility,
                            ),
                            onPressed: () => setState(() => _show = !_show),
                          ),
                          IconButton(
                            tooltip: tr('Копировать'),
                            icon: const Icon(Icons.copy),
                            onPressed: () => copyWithWipe(context, value.value),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(tr('Версия {0}', [_counter])),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('secret-save'),
                      onPressed: () => _save(value),
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: Text(
                        saved == null ? tr('В список') : tr('Обновить'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('secret-rotate'),
                      onPressed: () => _save(value, rotate: true),
                      icon: const Icon(Icons.autorenew),
                      label: Text(tr('Сменить')),
                    ),
                  ),
                ],
              ),
              Hint(
                short: tr(
                  'В списке хранятся только метка и версия. Само значение вычисляется заново.',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
