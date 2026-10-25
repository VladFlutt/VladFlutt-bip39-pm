import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Timer? _wipe;

/// Копирует секрет в буфер и стирает его через [ttl], если там всё ещё он.
Future<void> copyWithWipe(
  BuildContext context,
  String value, {
  String what = 'Скопировано',
  Duration? ttl = const Duration(seconds: 30),
}) async {
  await Clipboard.setData(ClipboardData(text: value));
  _wipe?.cancel();
  if (ttl != null) {
    _wipe = Timer(ttl, () async {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == value) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    });
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ttl == null ? what : '$what, сотрётся через ${ttl.inSeconds} с',
        ),
      ),
    );
  }
}
