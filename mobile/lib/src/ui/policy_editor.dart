import 'package:flutter/material.dart';

import '../rust/api/pm.dart';
import '../state/app_scope.dart';
import 'hint.dart';
import 'pro_gate.dart';
import '../l10n/tr.dart';

/// Готовые правила. Сайты, которые не принимают символы или длинные пароли, обычно
/// укладываются в одно из них.
List<RuleTemplate> get builtinTemplates => [
  RuleTemplate(name: tr('Стандарт'), policy: _p(20)),
  RuleTemplate(name: tr('Максимум'), policy: _p(32)),
  RuleTemplate(name: tr('Без символов'), policy: _p(20, symbols: false)),
  RuleTemplate(name: tr('Короткий'), policy: _p(12)),
  RuleTemplate(
    name: tr('Только цифры'),
    policy: _p(8, lower: false, upper: false, symbols: false),
  ),
];

PasswordPolicy _p(
  int length, {
  bool lower = true,
  bool upper = true,
  bool symbols = true,
}) => PasswordPolicy(
  length: length,
  lower: lower,
  upper: upper,
  digits: true,
  symbols: symbols,
);

/// Редактор правил пароля с шаблонами (Pro).
class PolicyEditor extends StatelessWidget {
  final PasswordPolicy policy;
  final ValueChanged<PasswordPolicy> onChanged;
  final bool initiallyExpanded;
  final String? title;

  const PolicyEditor({
    super.key,
    required this.policy,
    required this.onChanged,
    this.initiallyExpanded = false,
    this.title,
  });

  PasswordPolicy _with({
    int? length,
    bool? lower,
    bool? upper,
    bool? digits,
    bool? symbols,
  }) => PasswordPolicy(
    length: length ?? policy.length,
    lower: lower ?? policy.lower,
    upper: upper ?? policy.upper,
    digits: digits ?? policy.digits,
    symbols: symbols ?? policy.symbols,
  );

  Future<void> _saveTemplate(BuildContext context) async {
    if (!await requirePro(context, tr('Свои шаблоны правил'))) return;
    if (!context.mounted) return;
    final state = AppScope.of(context);
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Сохранить как шаблон')),
        content: TextField(
          key: const Key('template-name'),
          controller: name,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('Например, «Банк»')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('Отмена')),
          ),
          FilledButton(
            key: const Key('template-save'),
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Сохранить')),
          ),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await state.saveTemplate(
        RuleTemplate(name: name.text.trim(), policy: policy),
      );
    }
  }

  Future<void> _apply(BuildContext context, RuleTemplate t) async {
    if (await requirePro(context, tr('Шаблоны правил'))) onChanged(t.policy);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final enabled = [
      policy.lower,
      policy.upper,
      policy.digits,
      policy.symbols,
    ].where((v) => v).length;
    // Последний включённый класс выключить нельзя: нужен хотя бы один.
    ValueChanged<bool>? guard(bool on, PasswordPolicy Function(bool) f) =>
        on && enabled == 1 ? null : (v) => onChanged(f(v));
    final all = [...builtinTemplates, ...state.templates];
    return Card(
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Text(title ?? tr('Правила пароля')),
        subtitle: Text(policy.canonical()),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in all)
                  InputChip(
                    key: Key('template-${t.name}'),
                    label: Text(t.name),
                    selected: t.policy == policy,
                    showCheckmark: false,
                    onPressed: () => _apply(context, t),
                    onDeleted: state.templates.contains(t)
                        ? () => state.removeTemplate(t)
                        : null,
                  ),
                ActionChip(
                  key: const Key('template-add'),
                  avatar: const Icon(Icons.add, size: 18),
                  label: Text(tr('Шаблон')),
                  onPressed: () => _saveTemplate(context),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: ProBadge(),
                ),
              ],
            ),
          ),
          ListTile(
            title: Text(tr('Длина: {0}', [policy.length])),
            subtitle: Slider(
              min: 8,
              max: 64,
              divisions: 56,
              value: policy.length.toDouble(),
              onChanged: (v) => onChanged(_with(length: v.round())),
            ),
          ),
          SwitchListTile(
            title: Text(tr('Строчные a–z')),
            value: policy.lower,
            onChanged: guard(policy.lower, (v) => _with(lower: v)),
          ),
          SwitchListTile(
            title: Text(tr('Заглавные A–Z')),
            value: policy.upper,
            onChanged: guard(policy.upper, (v) => _with(upper: v)),
          ),
          SwitchListTile(
            title: Text(tr('Цифры 0–9')),
            value: policy.digits,
            onChanged: guard(policy.digits, (v) => _with(digits: v)),
          ),
          SwitchListTile(
            title: Text(tr('Символы !#\$%…')),
            value: policy.symbols,
            onChanged: guard(policy.symbols, (v) => _with(symbols: v)),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Hint(
              short: tr(
                'Меняйте правила, только если сайт не принимает пароль. Они сохраняются в списке.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
