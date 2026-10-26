import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart'
    show
        DropdownButtonFormField,
        DropdownMenuItem,
        InputDecoration,
        TextFormField,
        Material;
import 'package:flutter/widgets.dart';

class TaskZonePicker extends StatefulWidget {
  const TaskZonePicker({
    super.key,
    required this.value,
    required this.enabled,
    required this.i18n,
    required this.onChanged,
  });
  final String value;
  final bool enabled;
  final DshI18n i18n;
  final void Function(String) onChanged;
  @override
  State<TaskZonePicker> createState() => _TaskZonePickerState();
}

class _TaskZonePickerState extends State<TaskZonePicker> {
  late final controller = TextEditingController(text: widget.value);
  final focus = FocusNode();
  @override
  void didUpdateWidget(TaskZonePicker old) {
    super.didUpdateWidget(old);
    if (controller.text != widget.value) {
      controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focus,
      optionsBuilder: (v) {
        final query = v.text.trim().toLowerCase();
        return taskTimeZones().where(
          (z) => z
              .toLowerCase()
              .replaceAll('_', ' ')
              .contains(query.replaceAll('_', ' ')),
        );
      },
      onSelected: widget.onChanged,
      fieldViewBuilder: (context, controller, focus, submit) => TextFormField(
        controller: controller,
        focusNode: focus,
        enabled: widget.enabled,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          labelText: widget.i18n.t('schedule.manager', 'timing.zone'),
          hintText: widget.i18n.t('schedule.manager', 'timing.zoneSearch'),
          isDense: true,
        ),
      ),
      optionsViewBuilder: (context, select, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: context.dsh.bgBase,
          elevation: 4,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 310, maxHeight: 240),
            child: ListView.builder(
              padding: const EdgeInsets.all(4),
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, index) {
                final zone = options.elementAt(index);
                return DshButton(
                  onPressed: () => select(zone),
                  child: Text(zone),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}

class TaskCronBuilder extends StatelessWidget {
  const TaskCronBuilder({
    super.key,
    required this.expression,
    required this.enabled,
    required this.i18n,
    required this.onChanged,
  });
  final String expression;
  final bool enabled;
  final DshI18n i18n;
  final void Function(String) onChanged;
  String t(String key) => i18n.t('schedule.manager', key);
  @override
  Widget build(BuildContext context) {
    final parsed = parseTaskCron(expression),
        shape = parsed == null ? null : taskCronShape(parsed);
    if (shape == null) return const SizedBox.shrink();
    final kind = shape['kind'] as String;
    void change(Map<String, Object?> next) =>
        onChanged(taskCronExpression(next));
    Widget numeric(String field, int limit, String label) => Expanded(
      child: DropdownButtonFormField<int>(
        key: ValueKey('$kind-$field-${shape[field]}'),
        initialValue: shape[field]! as int,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          for (var n = 0; n <= limit; n++)
            DropdownMenuItem(value: n, child: Text('$n')),
        ],
        onChanged: enabled
            ? (v) {
                if (v != null) change({...shape, field: v});
              }
            : null,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('cron-$kind'),
          initialValue: kind,
          decoration: InputDecoration(
            labelText: t('cronForm.frequency'),
            isDense: true,
          ),
          items: [
            for (final k in [
              'minutely',
              'hourly',
              'daily',
              'weekly',
              'monthly',
            ])
              DropdownMenuItem(
                value: k,
                child: Text(
                  t(switch (k) {
                    'minutely' => 'rule.everyMinutes',
                    'hourly' => 'rule.everyHours',
                    _ => 'cronForm.$k',
                  }),
                ),
              ),
          ],
          onChanged: enabled
              ? (v) {
                  if (v == null || v == kind) return;
                  change({
                    'kind': v,
                    'hour': shape['hour'] ?? 9,
                    'minute': shape['minute'] ?? 0,
                    'step': 1,
                    if (v == 'weekly') 'weekdays': [1],
                    if (v == 'monthly') 'days': [1],
                  });
                }
              : null,
        ),
        const SizedBox(height: 16),
        if (kind == 'hourly' || kind == 'minutely')
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('$kind-step-${shape['step']}'),
                  initialValue: shape['step']! as int,
                  decoration: InputDecoration(
                    labelText: t('timing.interval'),
                    isDense: true,
                  ),
                  items: [
                    for (
                      var step = 1;
                      step <= (kind == 'hourly' ? 23 : 59);
                      step++
                    )
                      DropdownMenuItem(value: step, child: Text('$step')),
                  ],
                  onChanged: enabled
                      ? (v) {
                          if (v != null) change({...shape, 'step': v});
                        }
                      : null,
                ),
              ),
              if (kind == 'hourly') ...[
                const SizedBox(width: 12),
                numeric('minute', 59, t('cronForm.atMinute')),
              ],
            ],
          ),
        if (!['hourly', 'minutely'].contains(kind))
          Row(
            children: [
              numeric('hour', 23, t('timing.hour')),
              const SizedBox(width: 12),
              numeric('minute', 59, t('timing.minute')),
            ],
          ),
        if (kind == 'weekly' || kind == 'monthly') ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (var d = 1; d <= (kind == 'weekly' ? 7 : 31); d++)
                Builder(
                  builder: (context) {
                    final key = kind == 'weekly' ? 'weekdays' : 'days',
                        days = (shape[key] as List).cast<int>();
                    final selected = days.contains(d);
                    return DshButton(
                      variant: selected
                          ? DshButtonVariant.toolbar
                          : DshButtonVariant.ghost,
                      size: DshButtonSize.sm,
                      semanticLabel: i18n.t(
                        'schedule.manager',
                        kind == 'weekly'
                            ? 'rule.weekdayOption'
                            : 'cronForm.dateOption',
                        params: {'weekday': d, 'day': d},
                      ),
                      onPressed: !enabled || (selected && days.length == 1)
                          ? null
                          : () {
                              final next = days.toSet();
                              if (!next.remove(d)) next.add(d);
                              change({...shape, key: next.toList()..sort()});
                            },
                      child: Semantics(selected: selected, child: Text('$d')),
                    );
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }
}
