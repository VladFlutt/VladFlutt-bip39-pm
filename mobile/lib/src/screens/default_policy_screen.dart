import 'package:flutter/material.dart';

import '../rust/api/pm.dart';
import '../state/app_scope.dart';
import '../ui/hint.dart';
import '../ui/policy_editor.dart';
import '../ui/wallpaper.dart';

/// Правило для новых сайтов текущего профиля. Сохранённые сайты не меняются.
class DefaultPolicyScreen extends StatefulWidget {
  const DefaultPolicyScreen({super.key});

  @override
  State<DefaultPolicyScreen> createState() => _DefaultPolicyScreenState();
}

class _DefaultPolicyScreenState extends State<DefaultPolicyScreen> {
  late PasswordPolicy _policy = AppScope.of(context).newSitePolicy;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return CryptoWallpaper(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Правило для новых сайтов'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            PolicyEditor(
              policy: _policy,
              initiallyExpanded: true,
              title: 'Новые сайты',
              onChanged: (p) => setState(() => _policy = p),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('default-save'),
              onPressed: () async {
                await state.setDefaultPolicy(_policy);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Сохранить'),
            ),
            TextButton(
              onPressed: () async {
                await state.setDefaultPolicy(null);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text(
                'Вернуть стандартное (20 символов, все классы)',
              ),
            ),
            const Hint(
              short:
                  'Меняет правило только для сайтов, которые вы добавите дальше. '
                  'Пароли уже сохранённых сайтов останутся прежними.',
              learn:
                  'Правило входит в вычисление пароля. Если открыть сайт на другом устройстве '
                  'без переноса списка, пароль посчитается по стандартному правилу.',
            ),
          ],
        ),
      ),
    );
  }
}
