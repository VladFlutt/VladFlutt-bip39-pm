import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../rust/api/pm.dart';
import '../services/qr_frames.dart';
import '../state/app_scope.dart';
import '../ui/hint.dart';
import '../ui/wallpaper.dart';

/// Перенос и резервная копия списка сайтов, секретов и шаблонов текущего профиля.
class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final _paste = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  Future<void> _import(String code) async {
    setState(() => _error = null);
    try {
      final r = await AppScope.of(context).importCode(code);
      setState(_paste.clear);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(importSummary(r), key: const Key('import-result')),
          ),
        );
      }
    } on AnyhowException catch (e) {
      setState(() => _error = e.message.replaceFirst('ошибка индекса: ', ''));
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (code != null && mounted) await _import(code);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final count =
        state.accounts.length + state.secrets.length + state.templates.length;
    return CryptoWallpaper(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Перенос и копия'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Отправить с этого телефона', style: text.titleMedium),
            Text('Профиль «${state.profile.name}», записей: $count'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('show-qr'),
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('Показать QR'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => QrScreen(code: state.exportCode()),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  key: const Key('copy-code'),
                  icon: const Icon(Icons.copy),
                  label: const Text('Копировать код'),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: state.exportCode()),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Код переноса скопирован'),
                        ),
                      );
                    }
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('Поделиться'),
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(
                      text: state.exportCode(),
                      subject: 'ManagerBIP: код переноса',
                    ),
                  ),
                ),
              ],
            ),
            const Hint(
              short:
                  'Код зашифрован ключом из вашей фразы: открыть его сможет только ManagerBIP '
                  'с той же фразой и passphrase. Его можно хранить в облаке как резервную копию.',
              learn:
                  'Пароли восстанавливаются из одной фразы, но номера версий, особые правила, '
                  'секреты и шаблоны живут в списке. Код переноса сохраняет именно их.',
            ),
            const Divider(height: 32),
            Text('Принять на этот телефон', style: text.titleMedium),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              key: const Key('scan-qr'),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Сканировать QR'),
              onPressed: _scan,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('paste-code'),
              controller: _paste,
              minLines: 2,
              maxLines: 4,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: 'или вставьте код PMX1:…',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('import-code'),
              onPressed: _paste.text.trim().isEmpty
                  ? null
                  : () => _import(_paste.text),
              child: const Text('Добавить в список'),
            ),
            const Hint(
              short:
                  'Записи добавляются к вашим. Если сайт есть в обоих списках, '
                  'остаётся более новая версия пароля.',
            ),
          ],
        ),
      ),
    );
  }
}

String importSummary(MergeResult r) =>
    'Добавлено: ${r.added}, обновлено: ${r.updated}, без изменений: ${r.kept}';

/// QR-кадры кода переноса по очереди; второй телефон собирает их в любом порядке.
class QrScreen extends StatefulWidget {
  final String code;

  const QrScreen({super.key, required this.code});

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> {
  late final _frames = splitFrames(widget.code);
  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (_frames.length > 1) {
      _timer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => setState(() => _i = (_i + 1) % _frames.length),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR для переноса')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: QrImageView(
                  data: _frames[_i],
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.L,
                ),
              ),
              const SizedBox(height: 16),
              Text('Кадр ${_i + 1} из ${_frames.length}'),
              const SizedBox(height: 8),
              const Text(
                'На втором телефоне: ManagerBIP → Настройки → Перенос и копия → Сканировать QR. '
                'Держите камеру, пока не соберутся все кадры.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Сканер QR-кадров. Возвращает собранный код переноса.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _collector = FrameCollector();
  bool _done = false;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    var changed = false;
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && _collector.add(v)) changed = true;
    }
    if (!changed) return;
    if (_collector.done) {
      _done = true;
      Navigator.of(context).pop(_collector.text);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _collector.total;
    return Scaffold(
      appBar: AppBar(title: const Text('Сканировать QR')),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: _onDetect,
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Камера недоступна: ${error.errorCode.name}. '
                    'Разрешите доступ к камере или вставьте код вручную.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                LinearProgressIndicator(
                  value: total == null ? 0 : _collector.received / total,
                ),
                const SizedBox(height: 8),
                Text(
                  total == null
                      ? 'Наведите камеру на QR на другом телефоне'
                      : 'Собрано кадров: ${_collector.received} из $total',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
