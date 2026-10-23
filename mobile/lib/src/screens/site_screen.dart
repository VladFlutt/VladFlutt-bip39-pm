import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rust/api/pm.dart';
import '../state/app_scope.dart';
import '../ui/hint.dart';
import '../ui/wallpaper.dart';

/// Через сколько стирать скопированный пароль из буфера обмена.
const clipboardTtl = Duration(seconds: 30);

/// Карточка сайта: пароль вычисляется на лету при любом изменении полей.
class SiteScreen extends StatefulWidget {
  final Account? account;

  const SiteScreen({super.key, this.account});

  @override
  State<SiteScreen> createState() => _SiteScreenState();
}

class _SiteScreenState extends State<SiteScreen> {
  late final _site = TextEditingController(text: widget.account?.domain);
  late final _login = TextEditingController(text: widget.account?.login);
  late int _counter = widget.account?.counter ?? 1;
  late PasswordPolicy _policy =
      widget.account?.policy ?? PasswordPolicy.defaultPolicy();
  bool _show = false;
  Timer? _clipboardTimer;

  @override
  void dispose() {
    _site.dispose();
    _login.dispose();
    super.dispose();
  }

  (Derived?, String?) _derive() {
    if (_site.text.trim().isEmpty || _login.text.trim().isEmpty) {
      return (null, null);
    }
    try {
      final d = AppScope.of(context).vault.derive(
        site: _site.text,
        login: _login.text,
        counter: _counter,
        policy: _policy,
      );
      return (d, null);
    } catch (e) {
      return (null, '$e');
    }
  }

  Future<void> _copy(String password) async {
    await Clipboard.setData(ClipboardData(text: password));
    _clipboardTimer?.cancel();
    _clipboardTimer = Timer(clipboardTtl, () async {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == password) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Пароль скопирован, сотрётся через ${clipboardTtl.inSeconds} с',
          ),
        ),
      );
    }
  }

  Future<void> _save(Derived d, {bool rotate = false}) async {
    final state = AppScope.of(context);
    final counter = rotate ? d.counter + 1 : d.counter;
    await state.save(
      Account(
        domain: d.domain,
        login: d.login,
        counter: counter,
        policy: _policy,
        note: widget.account?.note,
      ),
    );
    setState(() => _counter = counter);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            rotate ? 'Новый пароль, версия $counter' : 'Сохранено в списке',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final (derived, error) = _derive();
    final saved = derived == null
        ? null
        : state.find(derived.domain, derived.login);
    final scheme = Theme.of(context).colorScheme;
    return CryptoWallpaper(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(widget.account?.domain ?? 'Новый сайт'),
          actions: [
            if (saved != null)
              IconButton(
                tooltip: 'Убрать из списка',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await state.remove(saved);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              key: const Key('site'),
              controller: _site,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Сайт',
                hintText: 'github.com или ссылка',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('login'),
              controller: _login,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Логин или e-mail',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (derived != null && derived.domain != _site.text.trim())
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 12),
                child: Text(
                  'Сайт: ${derived.domain}',
                  style: TextStyle(color: scheme.primary),
                ),
              ),
            const Hint(
              learn:
                  'Адрес сокращается до основного домена: «https://www.github.com/login» и «github.com» '
                  'дают один и тот же пароль. Регистр букв в логине тоже не важен.',
            ),
            if (error != null)
              Text(error, style: TextStyle(color: scheme.error)),
            if (derived != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              _show
                                  ? derived.password
                                  : '•' * derived.password.length,
                              key: const Key('password'),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 18,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: _show ? 'Скрыть' : 'Показать',
                            icon: Icon(
                              _show ? Icons.visibility_off : Icons.visibility,
                            ),
                            onPressed: () => setState(() => _show = !_show),
                          ),
                          IconButton(
                            key: const Key('copy'),
                            tooltip: 'Копировать',
                            icon: const Icon(Icons.copy),
                            onPressed: () => _copy(derived.password),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Проверка: ${derived.checkWords} · версия ${derived.counter}',
                        key: const Key('check'),
                      ),
                    ],
                  ),
                ),
              ),
              const Hint(
                learn:
                    'Два проверочных слова помогают сверить пароль на разных устройствах, не показывая его. '
                    'Версия растёт, когда вы меняете пароль на сайте.',
              ),
              _PolicyEditor(
                policy: _policy,
                onChanged: (p) => setState(() => _policy = p),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('save'),
                      onPressed: () => _save(derived),
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: Text(saved == null ? 'В список' : 'Обновить'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('rotate'),
                      onPressed: () => _save(derived, rotate: true),
                      icon: const Icon(Icons.autorenew),
                      label: const Text('Сменить'),
                    ),
                  ),
                ],
              ),
              const Hint(
                short: '«Сменить» выдаёт новый пароль для этого сайта. Старый перестанет совпадать.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PolicyEditor extends StatelessWidget {
  final PasswordPolicy policy;
  final ValueChanged<PasswordPolicy> onChanged;

  const _PolicyEditor({required this.policy, required this.onChanged});

  PasswordPolicy _with({
    int? length,
    bool? lower,
    bool? upper,
    bool? digits,
    bool? symbols,
  }) => PasswordPolicy(
    length: length ?? policy.length,
    lower: lower ?? policy.lower,
    upper: upper ?? policy.upper,
    digits: digits ?? policy.digits,
    symbols: symbols ?? policy.symbols,
  );

  @override
  Widget build(BuildContext context) {
    final enabled = [
      policy.lower,
      policy.upper,
      policy.digits,
      policy.symbols,
    ].where((v) => v).length;
    // Последний включённый класс выключить нельзя: нужен хотя бы один.
    ValueChanged<bool>? guard(bool on, PasswordPolicy Function(bool) f) =>
        on && enabled == 1 ? null : (v) => onChanged(f(v));
    return Card(
      child: ExpansionTile(
        title: const Text('Правила пароля'),
        subtitle: Text(policy.canonical()),
        children: [
          ListTile(
            title: Text('Длина: ${policy.length}'),
            subtitle: Slider(
              min: 8,
              max: 64,
              divisions: 56,
              value: policy.length.toDouble(),
              onChanged: (v) => onChanged(_with(length: v.round())),
            ),
          ),
          SwitchListTile(
            title: const Text('Строчные a–z'),
            value: policy.lower,
            onChanged: guard(policy.lower, (v) => _with(lower: v)),
          ),
          SwitchListTile(
            title: const Text('Заглавные A–Z'),
            value: policy.upper,
            onChanged: guard(policy.upper, (v) => _with(upper: v)),
          ),
          SwitchListTile(
            title: const Text('Цифры 0–9'),
            value: policy.digits,
            onChanged: guard(policy.digits, (v) => _with(digits: v)),
          ),
          SwitchListTile(
            title: const Text('Символы !#\$%…'),
            value: policy.symbols,
            onChanged: guard(policy.symbols, (v) => _with(symbols: v)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Hint(
              short: 'Меняйте правила, только если сайт не принимает пароль. Они сохраняются в списке.',
            ),
          ),
        ],
      ),
    );
  }
}
