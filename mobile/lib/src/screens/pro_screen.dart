import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../state/app_scope.dart';
import '../ui/hint.dart';
import '../ui/wallpaper.dart';
import '../l10n/tr.dart';

/// Возможности Pro. `ready: false` — появится в обновлении, ключ уже подойдёт.
List<(IconData, String, bool)> get _features => [
  (Icons.sync_alt, tr('Перенос списка сайтов по QR и резервная копия'), true),
  (
    Icons.key_outlined,
    tr('PIN-коды, кодовые слова, пароли Wi‑Fi и ключи SSH из той же фразы'),
    true,
  ),
  (Icons.people_outline, tr('Несколько профилей и скрытый профиль'), true),
  (Icons.tune, tr('Шаблоны правил и правило для новых сайтов'), true),
  (
    Icons.password,
    tr('Автозаполнение паролей в приложениях и браузере'),
    false,
  ),
  (Icons.verified_user_outlined, tr('Коды двухфакторной защиты (2FA)'), false),
];

/// Экран Pro: что даёт, где купить ключ, ввод ключа.
class ProScreen extends StatefulWidget {
  const ProScreen({super.key});

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  final _key = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() => _error = null);
    try {
      await AppScope.of(context).activatePro(_key.text);
      _key.clear();
    } on AnyhowException catch (e) {
      setState(() => _error = trError(e));
    }
  }

  Future<void> _open(String url) async {
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      setState(() => _error = tr('Не удалось открыть ссылку'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final pro = state.pro;
    final shops = proShops.where((s) => s.url.isNotEmpty).toList();
    return CryptoWallpaper(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('ManagerBIP Pro'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: pro != null ? scheme.primaryContainer : null,
              child: ListTile(
                key: const Key('pro-status'),
                leading: Icon(
                  pro != null
                      ? Icons.verified
                      : Icons.workspace_premium_outlined,
                  color: scheme.primary,
                ),
                title: Text(
                  pro != null ? tr('Pro активирован') : tr('Бесплатная версия'),
                ),
                subtitle: Text(
                  pro != null
                      ? tr('Ключ №{0}, выпущен {1}', [pro.serial, pro.issued])
                      : tr(
                          'Разовая покупка, без подписки. Пароли бесплатны всегда.',
                        ),
                ),
              ),
            ),
            if (pro == null && state.learning)
              Hint(
                short: tr(
                  'В учебном режиме все функции Pro открыты: попробуйте их на тестовой фразе.',
                ),
              ),
            const SizedBox(height: 8),
            Text(tr('Что даёт Pro'), style: text.titleMedium),
            for (final (icon, title, ready) in _features)
              ListTile(
                leading: Icon(icon),
                title: Text(title),
                trailing: ready
                    ? null
                    : Chip(
                        label: Text(tr('скоро')),
                        visualDensity: VisualDensity.compact,
                      ),
              ),
            Hint(
              short: tr(
                'Доступ к паролям не зависит от Pro: они всегда вычисляются из вашей фразы.',
              ),
              learn: tr(
                'Ключ Pro проверяется прямо на телефоне, без интернета и без аккаунта. После переустановки введите тот же ключ ещё раз.',
              ),
            ),
            if (pro == null) ...[
              const Divider(height: 32),
              // В Play-сборке без раздела о покупке: см. config.dart.
              if (store != 'play') ...[
                Text(tr('Купить ключ'), style: text.titleMedium),
                const SizedBox(height: 8),
                if (shops.isEmpty)
                  Text(
                    tr(
                      'Ключи продаются на Ozon, Wildberries и на сайте ManagerBIP.',
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in shops)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.shopping_bag_outlined),
                          label: Text(s.name),
                          onPressed: () => _open(s.url),
                        ),
                    ],
                  ),
                const SizedBox(height: 24),
              ],
              Text(tr('Активировать'), style: text.titleMedium),
              const SizedBox(height: 8),
              TextField(
                key: const Key('pro-key'),
                controller: _key,
                minLines: 2,
                maxLines: 4,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText: 'MBIP-XXXX-XXXX-…',
                  border: const OutlineInputBorder(),
                  errorText: _error,
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('pro-activate'),
                onPressed: _key.text.trim().isEmpty ? null : _activate,
                child: Text(tr('Активировать')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
