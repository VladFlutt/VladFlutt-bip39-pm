import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rust/api/pm.dart';
import '../state/app_scope.dart';
import '../ui/hint.dart';
import '../ui/policy_editor.dart';
import '../ui/wallpaper.dart';
import '../l10n/tr.dart';

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
      widget.account?.policy ?? AppScope.of(context).newSitePolicy;
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
            rotate
                ? tr('Новый пароль, версия {0}', [counter])
                : tr('Сохранено в списке'),
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
                            onPressed: () => _copy(derived.password),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr('Проверка: {0} · версия {1}', [
                          derived.checkWords,
                          derived.counter,
                        ]),
                        key: const Key('check'),
                      ),
                    ],
                  ),
                ),
              ),
              Hint(
                learn: tr(
                  'Два проверочных слова помогают сверить пароль на разных устройствах, не показывая его. Версия растёт, когда вы меняете пароль на сайте.',
                ),
              ),
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
                      onPressed: () => _save(derived),
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: Text(
                        saved == null ? tr('В список') : tr('Обновить'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('rotate'),
                      onPressed: () => _save(derived, rotate: true),
                      icon: const Icon(Icons.autorenew),
                      label: Text(tr('Сменить')),
                    ),
                  ),
                ],
              ),
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
