import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/accounts_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/mode_screen.dart';
import 'screens/onboarding_screen.dart';
import 'state/app_scope.dart';
import 'state/app_state.dart';
import 'l10n/tr.dart';
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
  final _navigator = GlobalKey<NavigatorState>();
  Phase _phase = Phase.chooseMode;
  AppLang _lang = appLang;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(_onState);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Блокировка закрывает все открытые поверх списка экраны: без ключа им нечего показывать.
  void _onState() {
    final phase = widget.state.phase;
    if (_phase == Phase.unlocked && phase != Phase.unlocked) {
      _navigator.currentState?.popUntil((r) => r.isFirst);
    }
    _phase = phase;
    if (_lang != appLang) {
      setState(() => _lang = appLang);
      // Тексты tr() не зависят от контекста: перестраиваем всё дерево, не трогая навигацию.
      void rebuild(Element e) => e
        ..markNeedsBuild()
        ..visitChildren(rebuild);
      (context as Element).visitChildren(rebuild);
    }
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
        navigatorKey: _navigator,
        title: 'ManagerBIP',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        locale: Locale(_lang.name),
        supportedLocales: [for (final l in AppLang.values) Locale(l.name)],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
