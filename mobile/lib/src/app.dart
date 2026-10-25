import 'package:flutter/material.dart';

import 'screens/accounts_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/mode_screen.dart';
import 'screens/onboarding_screen.dart';
import 'state/app_scope.dart';
import 'state/app_state.dart';
import 'ui/hint.dart';
import 'ui/wallpaper.dart';

class ManagerBipApp extends StatefulWidget {
  final AppState state;

  const ManagerBipApp({super.key, required this.state});

  @override
  State<ManagerBipApp> createState() => _ManagerBipAppState();
}

class _ManagerBipAppState extends State<ManagerBipApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Ушли в фон — ключ выгружается из памяти, вернуться можно только через биометрию.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused && widget.state.phase == Phase.unlocked) {
      widget.state.lock();
    }
  }

  ThemeData _theme(Brightness b) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFF7931A),
      tertiary: const Color(0xFF627EEA),
      brightness: b,
    ),
    useMaterial3: true,
  );

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: widget.state,
      child: MaterialApp(
        title: 'ManagerBIP',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        builder: (context, child) => Column(
          children: [
            const LearningBanner(),
            Expanded(child: child!),
          ],
        ),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final screen = switch (state.phase) {
      Phase.chooseMode => const ModeScreen(),
      Phase.loading => const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      ),
      Phase.onboarding => const OnboardingScreen(),
      Phase.locked => const LockScreen(),
      Phase.unlocked => const AccountsScreen(),
    };
    return CryptoWallpaper(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: screen,
      ),
    );
  }
}
