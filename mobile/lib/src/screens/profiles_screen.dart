import 'package:flutter/material.dart';

import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../ui/hint.dart';
import '../ui/pro_gate.dart';
import '../ui/wallpaper.dart';
import 'onboarding_screen.dart';
import '../l10n/tr.dart';

Future<String?> askText(
  BuildContext context, {
  required String title,
  String? hint,
  String? initial,
  bool obscure = false,
  String? action,
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
          child: Text(tr('Отмена')),
        ),
        FilledButton(
          key: const Key('ask-ok'),
          onPressed: () => Navigator.pop(d, true),
          child: Text(action ?? tr('Готово')),
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
    if (!await requirePro(context, tr('Несколько профилей'))) return;
    if (!context.mounted) return;
    final state = AppScope.of(context);
    final name = await askText(
      context,
      title: tr('Новый профиль'),
      hint: tr('Рабочий, Семья…'),
      action: tr('Далее'),
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
    if (!await requirePro(context, tr('Скрытый профиль'))) return;
    if (!context.mounted) return;
    final state = AppScope.of(context);
    final code = await askText(
      context,
      title: tr('Скрыть профиль «{0}»', [state.profile.title]),
      message: tr(
        'Профиль пропадёт из списка. Открыть его можно будет только этим кодом: Настройки → Профили → Открыть скрытый. Код не восстанавливается, но профиль всегда можно добавить заново по его фразе.',
      ),
      hint: tr('Код, не меньше 4 символов'),
      obscure: true,
      action: tr('Скрыть'),
    );
    if (code == null || !context.mounted) return;
    if (code.length < 4) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('Код слишком короткий'))));
      return;
    }
    await state.hideProfile(code);
  }

  Future<void> _openHidden(BuildContext context) async {
    final state = AppScope.of(context);
    final code = await askText(
      context,
      title: tr('Открыть скрытый профиль'),
      hint: tr('Код'),
      obscure: true,
      action: tr('Открыть'),
    );
    if (code == null || !context.mounted) return;
    final ok = await state.openHidden(code);
    if (!context.mounted) return;
    if (ok) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Профиль с таким кодом не найден'))),
      );
    }
  }

  Future<void> _rename(BuildContext context, Profile p) async {
    final state = AppScope.of(context);
    final name = await askText(
      context,
      title: tr('Название'),
      initial: p.title,
    );
    if (name != null) await state.renameProfile(p, name);
  }

  Future<void> _delete(BuildContext context, Profile p) async {
    final state = AppScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Удалить профиль «{0}»?', [p.title])),
        content: Text(
          tr(
            'Ключ и список профиля будут удалены с телефона. Пароли можно будет вернуть по его фразе.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('Отмена')),
          ),
          FilledButton(
            key: const Key('confirm-delete'),
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Удалить')),
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
          title: Text(tr('Профили')),
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
                  title: Text(p.title),
                  subtitle: p.hidden
                      ? Text(tr('Скрытый, открыт сейчас'))
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
                      PopupMenuItem(
                        value: 'rename',
                        child: Text(tr('Переименовать')),
                      ),
                      if (p.id != Profile.main.id)
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(tr('Удалить')),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('add-profile'),
              icon: const Icon(Icons.add),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr('Добавить профиль')),
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
                label: Text(tr('Скрыть «{0}»', [current.title])),
                onPressed: () => _hide(context),
              ),
            if (current.hidden)
              OutlinedButton.icon(
                key: const Key('unhide-profile'),
                icon: const Icon(Icons.visibility_outlined),
                label: Text(tr('Показывать в списке')),
                onPressed: state.unhideProfile,
              ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('open-hidden'),
              icon: const Icon(Icons.key_outlined),
              label: Text(tr('Открыть скрытый профиль')),
              onPressed: () => _openHidden(context),
            ),
            Hint(
              short: tr(
                'После блокировки телефон всегда открывает основной профиль. Скрытый профиль не виден, пока его не откроют кодом.',
              ),
              learn: tr(
                'Профиль — это отдельная фраза или та же фраза с другой passphrase. У каждого профиля свои пароли и свой список сайтов.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
