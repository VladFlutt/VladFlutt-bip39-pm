import 'package:flutter/material.dart';

import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../ui/hint.dart';
import '../ui/pro_gate.dart';
import '../ui/wallpaper.dart';
import 'onboarding_screen.dart';

Future<String?> askText(
  BuildContext context, {
  required String title,
  String? hint,
  String? initial,
  bool obscure = false,
  String action = 'Готово',
  String? message,
}) async {
  final c = TextEditingController(text: initial);
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message != null) ...[Text(message), const SizedBox(height: 12)],
          TextField(
            key: const Key('ask-text'),
            controller: c,
            autofocus: true,
            obscureText: obscure,
            decoration: InputDecoration(hintText: hint),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const Key('ask-ok'),
          onPressed: () => Navigator.pop(d, true),
          child: Text(action),
        ),
      ],
    ),
  );
  // Контроллер не освобождаем: диалог ещё анимирует закрытие, сборщик мусора справится.
  final v = c.text.trim();
  return ok == true && v.isNotEmpty ? v : null;
}

/// Профили: разные фразы или passphrase, у каждого свой список. Скрытый профиль
/// не показывается нигде и открывается только кодом.
class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key});

  Future<void> _add(BuildContext context) async {
    if (!await requirePro(context, 'Несколько профилей')) return;
    if (!context.mounted) return;
    final state = AppScope.of(context);
    final name = await askText(
      context,
      title: 'Новый профиль',
      hint: 'Рабочий, Семья…',
      action: 'Далее',
    );
    if (name == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CryptoWallpaper(
          child: OnboardingScreen(onProfile: (v) => state.addProfile(name, v)),
        ),
      ),
    );
  }

  Future<void> _hide(BuildContext context) async {
    if (!await requirePro(context, 'Скрытый профиль')) return;
    if (!context.mounted) return;
    final state = AppScope.of(context);
    final code = await askText(
      context,
      title: 'Скрыть профиль «${state.profile.name}»',
      message:
          'Профиль пропадёт из списка. Открыть его можно будет только этим кодом: '
          'Настройки → Профили → Открыть скрытый. Код не восстанавливается, '
          'но профиль всегда можно добавить заново по его фразе.',
      hint: 'Код, не меньше 4 символов',
      obscure: true,
      action: 'Скрыть',
    );
    if (code == null || !context.mounted) return;
    if (code.length < 4) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Код слишком короткий')));
      return;
    }
    await state.hideProfile(code);
  }

  Future<void> _openHidden(BuildContext context) async {
    final state = AppScope.of(context);
    final code = await askText(
      context,
      title: 'Открыть скрытый профиль',
      hint: 'Код',
      obscure: true,
      action: 'Открыть',
    );
    if (code == null || !context.mounted) return;
    final ok = await state.openHidden(code);
    if (!context.mounted) return;
    if (ok) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль с таким кодом не найден')),
      );
    }
  }

  Future<void> _rename(BuildContext context, Profile p) async {
    final state = AppScope.of(context);
    final name = await askText(context, title: 'Название', initial: p.name);
    if (name != null) await state.renameProfile(p, name);
  }

  Future<void> _delete(BuildContext context, Profile p) async {
    final state = AppScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Удалить профиль «${p.name}»?'),
        content: const Text(
          'Ключ и список профиля будут удалены с телефона. Пароли можно будет вернуть по его фразе.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('confirm-delete'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok == true) await state.deleteProfile(p);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final current = state.profile;
    return CryptoWallpaper(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Профили'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final p in [...state.profiles, if (current.hidden) current])
              Card(
                child: ListTile(
                  key: Key('profile-${p.name}'),
                  leading: Icon(
                    p.hidden
                        ? Icons.visibility_off_outlined
                        : p.id == current.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(p.name),
                  subtitle: p.hidden
                      ? const Text('Скрытый, открыт сейчас')
                      : null,
                  onTap: p.id == current.id
                      ? null
                      : () async {
                          await state.switchProfile(p);
                          if (context.mounted) {
                            Navigator.of(context).popUntil((r) => r.isFirst);
                          }
                        },
                  trailing: PopupMenuButton<String>(
                    key: Key('profile-menu-${p.name}'),
                    onSelected: (v) => switch (v) {
                      'rename' => _rename(context, p),
                      'delete' => _delete(context, p),
                      _ => null,
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: Text('Переименовать'),
                      ),
                      if (p.id != Profile.main.id)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Удалить'),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('add-profile'),
              icon: const Icon(Icons.add),
              label: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Добавить профиль'),
                  SizedBox(width: 8),
                  ProBadge(),
                ],
              ),
              onPressed: () => _add(context),
            ),
            const SizedBox(height: 8),
            if (current.id != Profile.main.id && !current.hidden)
              OutlinedButton.icon(
                key: const Key('hide-profile'),
                icon: const Icon(Icons.visibility_off_outlined),
                label: Text('Скрыть «${current.name}»'),
                onPressed: () => _hide(context),
              ),
            if (current.hidden)
              OutlinedButton.icon(
                key: const Key('unhide-profile'),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Показывать в списке'),
                onPressed: state.unhideProfile,
              ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('open-hidden'),
              icon: const Icon(Icons.key_outlined),
              label: const Text('Открыть скрытый профиль'),
              onPressed: () => _openHidden(context),
            ),
            const Hint(
              short:
                  'После блокировки телефон всегда открывает основной профиль. '
                  'Скрытый профиль не виден, пока его не откроют кодом.',
              learn:
                  'Профиль — это отдельная фраза или та же фраза с другой passphrase. '
                  'У каждого профиля свои пароли и свой список сайтов.',
            ),
          ],
        ),
      ),
    );
  }
}
