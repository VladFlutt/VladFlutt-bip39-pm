import 'package:flutter/material.dart';

import '../state/app_scope.dart';
import '../ui/hint.dart';
import '../ui/wallpaper.dart';
import '../ui/pro_gate.dart';
import 'default_policy_screen.dart';
import 'profiles_screen.dart';
import 'pro_screen.dart';
import 'transfer_screen.dart';
import '../l10n/tr.dart';
import '../ui/language_picker.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _forget(BuildContext context) async {
    final state = AppScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Забыть это устройство?')),
        content: Text(
          tr(
            'Ключ и список сайтов будут удалены с телефона. Пароли можно будет восстановить только по seed-фразе.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('Отмена')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Удалить')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await state.forgetDevice();
      if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  void _push(BuildContext context, Widget screen) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return CryptoWallpaper(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(tr('Настройки')),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              leading: const Icon(Icons.translate),
              title: Text(tr('Язык')),
              trailing: const LanguageButton(),
            ),
            ListTile(
              key: const Key('open-pro'),
              leading: Icon(
                state.isPro ? Icons.verified : Icons.workspace_premium_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('ManagerBIP Pro'),
              subtitle: Text(
                state.isPro ? tr('Активирован') : tr('Ввести или купить ключ'),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(context, const ProScreen()),
            ),
            ListTile(
              key: const Key('open-profiles'),
              leading: const Icon(Icons.people_outline),
              title: Text(tr('Профили')),
              subtitle: Text(tr('Открыт: {0}', [state.profile.title])),
              trailing: const ProBadge(),
              onTap: () => _push(context, const ProfilesScreen()),
            ),
            ListTile(
              key: const Key('open-transfer'),
              leading: const Icon(Icons.sync_alt),
              title: Text(tr('Перенос и резервная копия')),
              subtitle: Text(tr('QR или код для другого телефона')),
              trailing: const ProBadge(),
              onTap: () async {
                if (await requirePro(
                      context,
                      tr('Перенос и резервная копия'),
                    ) &&
                    context.mounted) {
                  _push(context, const TransferScreen());
                }
              },
            ),
            ListTile(
              key: const Key('open-default-policy'),
              leading: const Icon(Icons.tune),
              title: Text(tr('Правило для новых сайтов')),
              subtitle: Text(state.newSitePolicy.canonical()),
              trailing: const ProBadge(),
              onTap: () async {
                if (await requirePro(context, tr('Правило по умолчанию')) &&
                    context.mounted) {
                  _push(context, const DefaultPolicyScreen());
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: Text(tr('Отпечаток seed')),
              subtitle: Text(
                state.fingerprint,
                key: const Key('settings-fingerprint'),
              ),
            ),
            ListTile(
              leading: Icon(
                state.learning ? Icons.school_outlined : Icons.lock_outline,
              ),
              title: Text(
                state.learning ? tr('Режим обучения') : tr('Обычный режим'),
              ),
              subtitle: Text(tr('Сменить режим')),
              onTap: () {
                Navigator.of(context).popUntil((r) => r.isFirst);
                state.backToModeChoice();
              },
            ),
            Hint(
              learn: tr(
                'Отпечаток сверяют после восстановления на новом устройстве: те же три слова — значит, фраза и passphrase введены верно.',
              ),
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(tr('Забыть это устройство')),
              onTap: () => _forget(context),
            ),
          ],
        ),
      ),
    );
  }
}
