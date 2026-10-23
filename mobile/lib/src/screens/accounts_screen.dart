import 'package:flutter/material.dart';

import '../rust/api/pm.dart';
import '../state/app_scope.dart';
import '../ui/hint.dart';
import 'settings_screen.dart';
import 'site_screen.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  String _query = '';

  void _open([Account? account]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SiteScreen(account: account)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final q = _query.toLowerCase();
    final list = state.accounts
        .where((a) => a.domain.contains(q) || a.login.contains(q))
        .toList();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('ManagerBIP'),
        actions: [
          IconButton(
            tooltip: 'Заблокировать',
            icon: const Icon(Icons.lock_outline),
            onPressed: state.lock,
          ),
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add'),
        onPressed: _open,
        icon: const Icon(Icons.add),
        label: const Text('Сайт'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Поиск по сайтам и логинам',
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
          if (state.error != null) Hint(short: state.error),
          if (state.accounts.isEmpty)
            const Hint(
              short: 'Нажмите «+ Сайт», введите адрес и логин — пароль появится сразу.',
              learn:
                  'Список ниже — это индекс: здесь запоминаются сайты, номера версий паролей и особые '
                  'правила. Самих паролей в нём нет, он зашифрован ключом из вашей фразы.',
            ),
          for (final a in list)
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
                onTap: () => _open(a),
              ),
            ),
        ],
      ),
    );
  }
}
