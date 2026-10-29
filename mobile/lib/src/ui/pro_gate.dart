import 'package:flutter/material.dart';

import '../screens/pro_screen.dart';
import '../state/app_scope.dart';
import '../l10n/tr.dart';

/// Пропускает к Pro-функции или предлагает открыть экран Pro. `true` — можно продолжать.
Future<bool> requirePro(BuildContext context, String feature) async {
  if (AppScope.of(context).proActive) return true;
  final more = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.workspace_premium_outlined),
      title: Text(feature),
      content: Text(
        tr(
          'Это функция ManagerBIP Pro. Разовая покупка, без подписки. В учебном режиме её можно попробовать бесплатно.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(tr('Не сейчас')),
        ),
        FilledButton(
          key: const Key('pro-more'),
          onPressed: () => Navigator.pop(c, true),
          child: Text(tr('Подробнее')),
        ),
      ],
    ),
  );
  if (more == true && context.mounted) {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const ProScreen()));
  }
  return false;
}

/// Значок «Pro» рядом с пунктом меню, пока Pro не активирован.
class ProBadge extends StatelessWidget {
  const ProBadge({super.key});

  @override
  Widget build(BuildContext context) {
    if (AppScope.of(context).proActive) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Pro',
        style: TextStyle(fontSize: 11, color: scheme.onPrimaryContainer),
      ),
    );
  }
}
