import 'package:flutter/material.dart';

import '../state/app_scope.dart';
import '../ui/hint.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _failed = false;

  Future<void> _unlock() async {
    final ok = await AppScope.of(context).unlock();
    if (mounted) setState(() => _failed = !ok);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Выбор режима',
          icon: const Icon(Icons.arrow_back),
          onPressed: state.backToModeChoice,
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.fingerprint, size: 96),
              const SizedBox(height: 16),
              Text(
                'ManagerBIP заблокирован',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('unlock'),
                onPressed: _unlock,
                icon: const Icon(Icons.lock_open),
                label: const Text('Разблокировать'),
              ),
              if (_failed) ...[
                const SizedBox(height: 12),
                const Text(
                  'Не удалось подтвердить личность. Попробуйте ещё раз.',
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              const Hint(
                learn:
                    'На телефоне хранится не сама seed-фраза, а ключ приложения, выведенный из неё. '
                    'Биометрия или код устройства открывают этот ключ.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
