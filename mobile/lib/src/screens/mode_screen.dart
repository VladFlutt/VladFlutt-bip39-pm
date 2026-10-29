import 'package:flutter/material.dart';

import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../l10n/tr.dart';
import '../ui/language_picker.dart';

/// Первый экран при каждом запуске: обычная работа или обучение.
class ModeScreen extends StatelessWidget {
  const ModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                const Align(
                  alignment: Alignment.centerRight,
                  child: LanguageButton(),
                ),
                const Icon(Icons.key_rounded, size: 64),
                const SizedBox(height: 12),
                Text(
                  'ManagerBIP',
                  textAlign: TextAlign.center,
                  style: text.headlineLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  tr(
                    'Все пароли из одной seed-фразы BIP39. Без сервера и без облака.',
                  ),
                  textAlign: TextAlign.center,
                  style: text.bodyLarge,
                ),
                const SizedBox(height: 32),
                _ModeCard(
                  key: const Key('mode-normal'),
                  icon: Icons.lock_outline,
                  title: tr('Обычный режим'),
                  subtitle: tr(
                    'Ваша seed-фраза, настоящие пароли. Ключ хранится в защищённом хранилище телефона.',
                  ),
                  onTap: () => state.chooseMode(AppMode.normal),
                ),
                const SizedBox(height: 12),
                _ModeCard(
                  key: const Key('mode-learning'),
                  icon: Icons.school_outlined,
                  title: tr('Режим обучения'),
                  subtitle: tr(
                    'Тестовая фраза и подсказки на каждом шаге. Можно пробовать что угодно: ничего не сохраняется.',
                  ),
                  onTap: () => state.chooseMode(AppMode.learning),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(
                icon,
                size: 36,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
