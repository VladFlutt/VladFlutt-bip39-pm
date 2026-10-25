import 'package:flutter/material.dart';

import '../state/app_scope.dart';

/// Подсказка на экране. В обычном режиме — коротко, в учебном — подробно.
class Hint extends StatelessWidget {
  /// Показывается всегда; `null` — только в учебном режиме.
  final String? short;

  /// Дополнительное объяснение для учебного режима.
  final String? learn;

  const Hint({super.key, this.short, this.learn});

  @override
  Widget build(BuildContext context) {
    final learning = AppScope.of(context).learning;
    final text = [?short, if (learning) ?learn].join('\n\n');
    if (text.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: (learning ? scheme.tertiaryContainer : scheme.secondaryContainer)
          .withValues(alpha: 0.85),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              learning ? Icons.school_outlined : Icons.lightbulb_outline,
              size: 20,
              color: learning
                  ? scheme.onTertiaryContainer
                  : scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

/// Плашка учебного режима вверху экранов.
class LearningBanner extends StatelessWidget {
  const LearningBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AppScope.of(context).learning) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(
            'Учебный режим: тестовая фраза, пароли не настоящие, ничего не сохраняется',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onTertiary, fontSize: 12),
          ),
        ),
      ),
    );
  }
}
