import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rust/api/pm.dart';
import '../state/app_scope.dart';
import '../ui/hint.dart';
import '../ui/pro_gate.dart';
import '../ui/policy_editor.dart';
import '../ui/wallpaper.dart';
import '../l10n/tr.dart';

/// Через сколько стирать скопированный пароль из буфера обмена.
const clipboardTtl = Duration(seconds: 30);

/// Карточка сайта: генерация из фразы или свой пароль в зашифрованном индексе.
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
      widget.account?.policy ?? AppScope.of(context).newSitePolicy;
  late bool _custom = widget.account?.customPassword != null;
  late final _customPassword = TextEditingController(
    text: widget.account?.customPassword,
  );
  bool _saving = false;
  bool _show = false;
  Timer? _clipboardTimer;

  @override
  void dispose() {
    _site.dispose();
    _login.dispose();
    _customPassword.dispose();
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
      return (null, trError(e));
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
            tr('Пароль скопирован, сотрётся через {0} с', [
              clipboardTtl.inSeconds,
            ]),
          ),
        ),
      );
    }
  }

  Future<void> _setCustom(bool value) async {
    if (value && !await requirePro(context, tr('Свои пароли'))) return;
    if (!mounted) return;
    final (derived, _) = _derive();
    final saved = derived == null
        ? null
        : AppScope.of(context).find(derived.domain, derived.login);
    setState(() {
      if (saved != null && saved.customPassword != null) {
        _counter = value ? saved.counter : saved.counter + 1;
      }
      _custom = value;
      _show = false;
    });
  }

  Future<void> _save(Derived d, {bool rotate = false}) async {
    final state = AppScope.of(context);
    if (_saving || (_custom && _customPassword.text.isEmpty)) return;
    final current = state.find(d.domain, d.login);
    final changed =
        current != null &&
        current.customPassword != (_custom ? _customPassword.text : null);
    if (_custom &&
        (current == null || changed) &&
        !await requirePro(context, tr('Свои пароли'))) {
      return;
    }
    if (!mounted) return;
    final counter = rotate || changed
        ? (current?.counter ?? d.counter) + 1
        : d.counter;
    setState(() => _saving = true);
    try {
      await state.save(
        Account(
          domain: d.domain,
          login: d.login,
          counter: counter,
          policy: _policy,
          note: current?.note ?? widget.account?.note,
          customPassword: _custom ? _customPassword.text : null,
        ),
      );
      if (!mounted) return;
      setState(() => _counter = counter);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              rotate
                  ? tr('Новый пароль, версия {0}', [counter])
                  : tr('Сохранено в списке'),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(trError(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final (derived, error) = _derive();
    final saved = derived == null
        ? null
        : state.find(derived.domain, derived.login);
    final password = _custom ? _customPassword.text : derived?.password ?? '';
    final scheme = Theme.of(context).colorScheme;
    return CryptoWallpaper(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(widget.account?.domain ?? tr('Новый сайт')),
          actions: [
            if (saved != null)
              IconButton(
                tooltip: tr('Убрать из списка'),
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
              decoration: InputDecoration(
                labelText: tr('Сайт'),
                hintText: tr('github.com или ссылка'),
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
              decoration: InputDecoration(
                labelText: tr('Логин или e-mail'),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (derived != null && derived.domain != _site.text.trim())
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 12),
                child: Text(
                  tr('Сайт: {0}', [derived.domain]),
                  style: TextStyle(color: scheme.primary),
                ),
              ),
            Hint(
              learn: tr(
                'Адрес сокращается до основного домена: «https://www.github.com/login» и «github.com» дают один и тот же пароль. Регистр букв в логине тоже не важен.',
              ),
            ),
            if (error != null)
              Text(error, style: TextStyle(color: scheme.error)),
            if (derived != null) ...[
              SwitchListTile(
                key: const Key('custom-mode'),
                title: Row(
                  children: [
                    Text(tr('Свой пароль')),
                    const SizedBox(width: 8),
                    const ProBadge(),
                  ],
                ),
                value: _custom,
                onChanged: _saving ? null : _setCustom,
              ),
              if (_custom) ...[
                TextField(
                  key: const Key('custom-password'),
                  controller: _customPassword,
                  readOnly: !state.proActive,
                  obscureText: !_show,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: tr('Введите свой пароль'),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    tr(
                      'Свой пароль хранится в зашифрованном индексе. Для восстановления нужна резервная копия индекса: одной seed-фразы недостаточно.',
                    ),
                  ),
                ),
              ],
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
                              _show ? password : '•' * password.length,
                              key: const Key('password'),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 18,
                              ),
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
                            key: const Key('copy'),
                            tooltip: tr('Копировать'),
                            icon: const Icon(Icons.copy),
                            onPressed: password.isEmpty
                                ? null
                                : () => _copy(password),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _custom
                            ? tr('Свой пароль')
                            : tr('Проверка: {0} · версия {1}', [
                                derived.checkWords,
                                derived.counter,
                              ]),
                        key: const Key('check'),
                      ),
                    ],
                  ),
                ),
              ),
              if (!_custom)
                Hint(
                  learn: tr(
                    'Два проверочных слова помогают сверить пароль на разных устройствах, не показывая его. Версия растёт, когда вы меняете пароль на сайте.',
                  ),
                ),
              if (!_custom)
                PolicyEditor(
                  policy: _policy,
                  onChanged: (p) => setState(() => _policy = p),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('save'),
                      onPressed: _saving || (_custom && password.isEmpty)
                          ? null
                          : () => _save(derived),
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: Text(
                        saved == null ? tr('В список') : tr('Обновить'),
                      ),
                    ),
                  ),
                  if (!_custom) const SizedBox(width: 12),
                  if (!_custom)
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('rotate'),
                        onPressed: _saving || _custom
                            ? null
                            : () => _save(derived, rotate: true),
                        icon: const Icon(Icons.autorenew),
                        label: Text(tr('Сменить')),
                      ),
                    ),
                ],
              ),
              if (!_custom)
                Hint(
                  short: tr(
                    '«Сменить» выдаёт новый пароль для этого сайта. Старый перестанет совпадать.',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
