import 'dart:async';
import 'dart:math' as math;

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:flutter/widgets.dart';

String taskAbsolute(String instant, DshI18n i18n) {
  final at = DateTime.tryParse(instant)?.toLocal();
  if (at == null) return instant;
  String p(int n) => '$n'.padLeft(2, '0');
  if (i18n.locale == DshLocale.zh) {
    return '${at.month}月${at.day}日 ${p(at.hour)}:${p(at.minute)}';
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[at.month - 1]} ${at.day}, ${at.year}, ${p(at.hour)}:${p(at.minute)}';
}

String taskRelative(String instant, DshI18n i18n, DateTime now) {
  final at = DateTime.tryParse(instant);
  if (at == null) return instant;
  String t(String key, [Map<String, Object?> params = const {}]) =>
      i18n.t('schedule.manager', key, params: params);
  final difference = at.difference(now).inMilliseconds;
  if (difference == 0) return t('relative.now');
  final seconds = difference.abs() / 1000;
  final selected = const [
    ('day', 86400),
    ('hour', 3600),
    ('minute', 60),
    ('second', 1),
  ].firstWhere((u) => seconds >= u.$2, orElse: () => ('second', 1));
  final value = math.max(
    1,
    difference > 0
        ? (seconds / selected.$2).ceil()
        : (seconds / selected.$2).floor(),
  );
  final unit = t('unit.${selected.$1}.${value == 1 ? 'one' : 'other'}', {
    'count': value,
  });
  return t(difference > 0 ? 'relative.future' : 'relative.overdue', {
    'value': value,
    'unit': unit,
  });
}

class TaskNextRun extends StatefulWidget {
  const TaskNextRun({
    super.key,
    required this.instant,
    required this.i18n,
    this.prefix = '',
    this.style,
  });
  final String instant, prefix;
  final DshI18n i18n;
  final TextStyle? style;
  @override
  State<TaskNextRun> createState() => _TaskNextRunState();
}

class _TaskNextRunState extends State<TaskNextRun> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    '${widget.prefix}${taskAbsolute(widget.instant, widget.i18n)} (${taskRelative(widget.instant, widget.i18n, DateTime.now())})',
    style: widget.style,
  );
}
