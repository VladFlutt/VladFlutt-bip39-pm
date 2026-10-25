import 'package:flutter/widgets.dart';

import 'app_state.dart';

/// Даёт экранам доступ к [AppState] и перестраивает их при изменениях.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
