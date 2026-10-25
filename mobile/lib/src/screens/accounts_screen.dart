import 'package:flutter/material.dart';

import '../rust/api/pm.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../ui/hint.dart';
import '../ui/pro_gate.dart';
import 'profiles_screen.dart';
import 'secret_screen.dart';
import 'settings_screen.dart';
import 'site_screen.dart';

enum _Tab { sites, secrets }

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  String _query = '';
  _Tab _tab = _Tab.sites;

  void _push(Widget screen) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));

  Future<void> _add() async {
    if (_tab == _Tab.sites) return _push(const SiteScreen());
    if (await requirePro(context, 'Секреты из фразы') && mounted) {
      _push(const SecretScreen());
    }
  }

  Widget _profileTitle(AppState state) {
    if (state.profiles.length == 1 && !state.profile.hidden) {
      return const Text('ManagerBIP');
    }
    return PopupMenuButton<Profile?>(
      key: const Key('profile-switch'),
      tooltip: 'Профиль',
      onSelected: (p) =>
          p == null ? _push(const ProfilesScreen()) : state.switchProfile(p),
      itemBuilder: (_) => [
        for (final p in state.profiles)
          CheckedPopupMenuItem(
            value: p,
            checked: p.id == state.profile.id,
            child: Text(p.name),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: null, child: Text('Профили…')),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(state.profile.name, overflow: TextOverflow.ellipsis),
          ),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final q = _query.toLowerCase();
    final sites = state.accounts
        .where((a) => a.domain.contains(q) || a.login.contains(q))
        .toList();
    final secrets = state.secrets.where((s) => s.label.contains(q)).toList();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: _profileTitle(state),
        actions: [
          IconButton(
            tooltip: 'Заблокировать',
            icon: const Icon(Icons.lock_outline),
            onPressed: state.lock,
          ),
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _push(const SettingsScreen()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add'),
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(_tab == _Tab.sites ? 'Сайт' : 'Секрет'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          SegmentedButton<_Tab>(
            key: const Key('tabs'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: _Tab.sites,
                icon: Icon(Icons.language),
                label: Text('Сайты', key: Key('tab-sites')),
              ),
              ButtonSegment(
                value: _Tab.secrets,
                icon: Icon(Icons.key_outlined),
                label: Text('Секреты', key: Key('tab-secrets')),
              ),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: _tab == _Tab.sites
                  ? 'Поиск по сайтам и логинам'
                  : 'Поиск по секретам',
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
          if (state.error != null) Hint(short: state.error),
          if (_tab == _Tab.sites) ...[
            if (state.accounts.isEmpty)
              const Hint(
                short: 'Нажмите «+ Сайт», введите адрес и логин — пароль появится сразу.',
                learn:
                    'Список ниже — это индекс: здесь запоминаются сайты, номера версий паролей и особые '
                    'правила. Самих паролей в нём нет, он зашифрован ключом из вашей фразы.',
              ),
            for (final a in sites)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(a.domain.substring(0, 1).toUpperCase()),
                  ),
                  title: Text(a.domain),
                  subtitle: Text(a.login),
                  trailing: a.counter > 1
                      ? Chip(label: Text('v${a.counter}'))
                      : null,
                  onTap: () => _push(SiteScreen(account: a)),
                ),
              ),
          ] else ...[
            if (state.secrets.isEmpty)
              Hint(
                short: state.proActive
                    ? 'PIN-коды, кодовые слова, пароли Wi‑Fi и ключи SSH из той же фразы. '
                          'Нажмите «+ Секрет».'
                    : 'PIN-коды, кодовые слова, пароли Wi‑Fi и ключи SSH из той же фразы — '
                          'функция Pro.',
              ),
            for (final s in secrets)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(secretTypeIcons[s.kind])),
                  title: Text(s.label),
                  subtitle: Text(
                    s.kind == SecretType.ssh
                        ? secretTypeNames[s.kind]!
                        : '${secretTypeNames[s.kind]} · ${s.size}',
                  ),
                  trailing: s.counter > 1
                      ? Chip(label: Text('v${s.counter}'))
                      : null,
                  onTap: () => _push(SecretScreen(item: s)),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
