import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/rust/frb_generated.dart';
import 'src/state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(ManagerBipApp(state: AppState.device()));
}
