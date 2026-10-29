import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../state/app_scope.dart';

/// Кнопка выбора языка: English, Ελληνικά, Русский.
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return PopupMenuButton<AppLang>(
      key: const Key('language'),
      tooltip: tr('Язык'),
      initialValue: appLang,
      onSelected: state.setLang,
      itemBuilder: (_) => [
        for (final l in AppLang.values)
          PopupMenuItem(
            value: l,
            key: Key('lang-${l.name}'),
            child: Text(l.title),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language),
            const SizedBox(width: 6),
            Text(appLang.title),
          ],
        ),
      ),
    );
  }
}
