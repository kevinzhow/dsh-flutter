import 'dart:async';
import 'dart:math' as math;

import 'package:dsh_client/generated_job.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show Material, MaterialType, InkWell;
import 'package:flutter/widgets.dart';

bool _live(JobView row) =>
    const ['running', 'stopping'].contains(row.status.value);
bool _observable(JobView row) => _live(row) || row.output.total > 0;
List<JobView> orderedJobs(Iterable<JobView> rows) =>
    rows.toList()..sort((a, b) {
      if (_live(a) != _live(b)) return _live(a) ? -1 : 1;
      if (_live(a)) return a.startedAt.compareTo(b.startedAt);
      final finished = (b.finishedAt ?? b.startedAt).compareTo(
        a.finishedAt ?? a.startedAt,
      );
      return finished != 0 ? finished : a.startedAt.compareTo(b.startedAt);
    });

class JobListAction extends StatefulWidget {
  const JobListAction({
    super.key,
    required this.service,
    required this.sessionId,
    required this.i18n,
  });
  final JobsService service;
  final String sessionId;
  final DshI18n i18n;
  @override
  State<JobListAction> createState() => _JobListActionState();
}

class _JobListActionState extends State<JobListAction> {
  final panel = DshPanelController();
  final revision = ValueNotifier(0);
  StreamSubscription<int>? sub;
  void Function()? stopRows, stopOutput;
  Timer? clock, killTimer;
  String? expanded, killId, killPhase;
  bool? settledOpen;
  final cleared = <String>{};
  int now = DateTime.now().millisecondsSinceEpoch;
  String t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t('job', key, params: params);
  List<JobView> get rows =>
      orderedJobs(widget.service.model.rows[widget.sessionId] ?? const []);
  List<JobView> get live => rows.where(_live).toList();
  List<JobView> get settled =>
      rows.where((r) => !_live(r) && !cleared.contains(r.id)).toList();
  void refresh() {
    if (!mounted) return;
    revision.value++;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    panel.addListener(_panelChanged);
    stopRows = widget.service.watchRows(widget.sessionId);
    sub = widget.service.model.changed.changes.listen((_) {
      if (expanded != null && !rows.any((r) => r.id == expanded)) {
        expanded = null;
        stopOutput?.call();
        stopOutput = null;
      }
      if (killId != null &&
          !rows.any((r) => r.id == killId && r.status.value == 'running')) {
        killTimer?.cancel();
        killId = null;
        killPhase = null;
      }
      if (live.isEmpty && settled.isEmpty && panel.isOpen) panel.close();
      refresh();
    });
  }

  void _panelChanged() {
    clock?.cancel();
    clock = null;
    if (panel.isOpen) {
      now = DateTime.now().millisecondsSinceEpoch;
      clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (live.isNotEmpty) {
          now = DateTime.now().millisecondsSinceEpoch;
          refresh();
        }
      });
      _observe();
    } else {
      stopOutput?.call();
      stopOutput = null;
    }
    refresh();
  }

  void _observe() {
    stopOutput?.call();
    stopOutput = null;
    if (!panel.isOpen || expanded == null) return;
    final row = rows.where((r) => r.id == expanded).firstOrNull;
    if (row != null && _observable(row)) {
      stopOutput = widget.service.observe(widget.sessionId, row.id);
    }
  }

  @override
  void dispose() {
    panel.removeListener(_panelChanged);
    clock?.cancel();
    killTimer?.cancel();
    stopRows?.call();
    stopOutput?.call();
    unawaited(sub?.cancel());
    panel.dispose();
    revision.dispose();
    super.dispose();
  }

  String duration(JobView row) {
    final ms = math.max(
      0,
      (_live(row) ? now : row.finishedAt ?? row.startedAt) - row.startedAt,
    );
    final seconds = ms ~/ 1000;
    final minutes = seconds ~/ 60;
    final hours = minutes ~/ 60;
    return hours > 0
        ? t('duration.hours', {'hours': hours, 'minutes': minutes % 60})
        : minutes > 0
        ? t('duration.minutes', {'minutes': minutes, 'seconds': seconds % 60})
        : t('duration.seconds', {'seconds': seconds});
  }

  void _resetKill() {
    killTimer?.cancel();
    killId = null;
    killPhase = null;
    refresh();
  }

  void _kill(JobView row) {
    if (killId != row.id || killPhase != 'armed') {
      killTimer?.cancel();
      killId = row.id;
      killPhase = 'armed';
      killTimer = Timer(const Duration(seconds: 3), _resetKill);
      refresh();
      return;
    }
    killTimer?.cancel();
    killPhase = 'pending';
    refresh();
    final id = row.id;
    unawaited(
      widget.service
          .kill(widget.sessionId, id)
          .then(
            (_) {
              /* Admission remains pending until the roster changes. */
            },
            onError: (Object e) {
              if (!mounted || killId != id || killPhase != 'pending') return;
              killPhase = 'failed';
              killTimer = Timer(const Duration(seconds: 4), _resetKill);
              refresh();
            },
          ),
    );
  }

  DshStateDotState _dot(JobView row) => switch (row.status.value) {
    'running' => DshStateDotState.ongoing,
    'stopping' || 'killed' => DshStateDotState.warning,
    'completed' => DshStateDotState.done,
    _ => DshStateDotState.error,
  };
  DshTerminalLabels get labels => DshTerminalLabels(
    commandLine: (n) => t('terminal.commandLine', {'n': n}),
    signal: (s) => t('terminal.signal', {'signal': s}),
    exitCode: (c) => t('terminal.exitCode', {'code': c}),
    noExitCode: t('terminal.noExitCode'),
    running: t('terminal.running'),
    failed: t('terminal.failed'),
    done: t('terminal.done'),
    copy: t('terminal.copy'),
    copied: t('terminal.copied'),
    noOutput: t('terminal.noOutput'),
    collapse: t('terminal.collapse'),
    expand: (n) => t('terminal.expand', {'n': n}),
  );
  Widget _item(JobView row) {
    final open = expanded == row.id;
    final view = widget.service.model.observed[row.id];
    final status = t('status.${row.status.value}');
    final kill = killId == row.id ? killPhase : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                expanded: _observable(row) ? open : null,
                label: t(open ? 'row.collapseAria' : 'row.expandAria', {
                  'label': row.label,
                }),
                child: InkWell(
                  onTap: !_observable(row)
                      ? null
                      : () {
                          expanded = open ? null : row.id;
                          _observe();
                          refresh();
                        },
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        DshStateDot(_dot(row)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                row.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${row.kind} · ${row.progress ?? row.detail ?? status} · ${duration(row)}',
                                style: context.dsh.textStyle(
                                  '--dsw-font-xxs-12',
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_observable(row))
                          const DshIcon(DshIcons.chevronDown, size: 12),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (row.status.value == 'running')
              DshButton(
                size: DshButtonSize.sm,
                semanticLabel: kill == 'armed'
                    ? t('kill.confirm')
                    : kill == 'failed'
                    ? t('kill.failed')
                    : t('kill.stop', {'label': row.label}),
                onPressed: kill == 'pending' ? null : () => _kill(row),
                icon: const DshIcon(DshIcons.stop, size: 10),
                child: Text(
                  kill == 'armed'
                      ? t('kill.confirmAction')
                      : kill == 'failed'
                      ? t('kill.failed')
                      : '',
                ),
              ),
          ],
        ),
        if (open && view != null) ...[
          if (view.gapBefore) Text(t('output.gap')),
          if (view.error != null)
            Semantics(
              liveRegion: true,
              child: Text(t('output.error', {'error': view.error})),
            ),
          DshTerminalBlock(
            command: row.label,
            output: view.text,
            running: _live(row),
            copyText: row.label,
            runStateDot: false,
            labels: labels,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = live.isNotEmpty ? live.length : live.length + settled.length;
    if (count == 0) return const SizedBox.shrink();
    final label = t(
      'count.${live.isEmpty ? 'idle' : 'live'}.${count == 1 ? 'one' : 'other'}',
      {'count': count},
    );
    return DshAnchoredPanel(
      controller: panel,
      panelWidth: 640,
      align: DshPanelAlign.end,
      gap: 5,
      builder: (context, c) => DshButton(
        size: DshButtonSize.sm,
        onPressed: c.toggle,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (live.isNotEmpty) ...[
              const DshStateDot(DshStateDotState.ongoing),
              const SizedBox(width: 4),
            ],
            Text(label),
            const DshIcon(DshIcons.chevronDown, size: 12),
          ],
        ),
      ),
      panelBuilder: (context, c) => ValueListenableBuilder<int>(
        valueListenable: revision,
        builder: (context, _, _) => Material(
          type: MaterialType.transparency,
          child: DshDecoratedBox(
            decoration: BoxDecoration(
              color: context.dsh.bgBase,
              borderRadius: BorderRadius.circular(context.dsh.radiusLg),
              border: Border.all(
                width: .5,
                color: context.dsh.color('--dsw-alias-border-l3'),
              ),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(640, MediaQuery.sizeOf(context).width - 24),
                maxHeight: MediaQuery.sizeOf(context).height * .7,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (live.isNotEmpty) ...[
                      Text(t('section.live')),
                      for (final row in live) _item(row),
                    ],
                    if (settled.isNotEmpty) ...[
                      Row(
                        children: [
                          Expanded(
                            child: DshButton(
                              size: DshButtonSize.sm,
                              onPressed: () {
                                settledOpen = !(settledOpen ?? live.isEmpty);
                                refresh();
                              },
                              child: Text(
                                t('section.settledCount', {
                                  'count': settled.length,
                                }),
                              ),
                            ),
                          ),
                          DshButton(
                            size: DshButtonSize.sm,
                            onPressed: () {
                              for (final row in settled) {
                                cleared.add(row.id);
                              }
                              if (expanded != null &&
                                  cleared.contains(expanded)) {
                                expanded = null;
                                _observe();
                              }
                              if (live.isEmpty) c.close();
                              refresh();
                            },
                            child: Text(t('section.clear')),
                          ),
                        ],
                      ),
                      if (settledOpen ?? live.isEmpty)
                        for (final row in settled) _item(row),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
