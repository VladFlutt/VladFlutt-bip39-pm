import 'package:flutter/material.dart';

import '../state/app_scope.dart';
import '../ui/hint.dart';
import '../ui/wallpaper.dart';
import 'pro_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _forget(BuildContext context) async {
    final state = AppScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Забыть это устройство?'),
        content: const Text(
          'Ключ и список сайтов будут удалены с телефона. Пароли можно будет восстановить только по seed-фразе.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await state.forgetDevice();
      if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return CryptoWallpaper(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Настройки'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              key: const Key('open-pro'),
              leading: Icon(
                state.isPro ? Icons.verified : Icons.workspace_premium_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('ManagerBIP Pro'),
              subtitle: Text(
                state.isPro ? 'Активирован' : 'Ввести или купить ключ',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ProScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: const Text('Отпечаток seed'),
              subtitle: Text(
                state.fingerprint,
                key: const Key('settings-fingerprint'),
              ),
            ),
            ListTile(
              leading: Icon(
                state.learning ? Icons.school_outlined : Icons.lock_outline,
              ),
              title: Text(state.learning ? 'Режим обучения' : 'Обычный режим'),
              subtitle: const Text('Сменить режим'),
              onTap: () {
                Navigator.of(context).popUntil((r) => r.isFirst);
                state.backToModeChoice();
              },
            ),
            const Hint(
              learn:
                  'Отпечаток сверяют после восстановления на новом устройстве: те же три слова — '
                  'значит, фраза и passphrase введены верно.',
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('Забыть это устройство'),
              onTap: () => _forget(context),
            ),
          ],
        ),
      ),
    );
  }
}
