import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_feature_chat/src/process_layout.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

class _WorkFixture extends StatefulWidget {
  const _WorkFixture(this.ctx, this.family);
  final ParityContext ctx;
  final String family;
  @override
  State<_WorkFixture> createState() => _WorkFixtureState();
}

class _WorkFixtureState extends State<_WorkFixture> {
  bool _open = false;
  late final prefs = ChatPreferences()
    ..setMode(
      TranscriptViewMode.values.byName(
        widget.ctx.props['mode'] as String? ?? 'standard',
      ),
    )
    ..setTiming(
      widget.ctx.props['nextInput'] == true
          ? CollapseTiming.nextInput
          : CollapseTiming.completion,
    );
  @override
  void dispose() {
    prefs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.ctx.props;
    final i18n = DshI18n(DshLocale.fromTag(widget.ctx.locale));
    ConvEvent ev(int seq, int time, String type, Map<String, Object?> data) =>
        ConvEvent(
          EventEntry({'seq': seq, 'time': time, 'type': type, 'data': data}),
        );
    final turn = TurnLocation(
      turn: 1,
      start: p['partial'] == true
          ? null
          : ev(1, 1000, 'turn/start', {'turn': 1}),
      end: ev(9, 1000 + (p['elapsed'] as int? ?? 5000), 'turn/end', {
        'turn': 1,
        'reason': {'kind': p['reason'] ?? 'completed'},
      }),
      status: BoundaryStatus.closed,
      steps: const [],
      data: LocationDataStore(),
    );
    const spec = TurnProcessData(
      turn: 1,
      controlAnchorSeq: 1,
      processStartSeq: 1,
      answerAnchorSeq: 8,
      answerStep: 2,
      inlineReasoning: false,
      messageCount: 1,
      toolCallCount: 2,
      subagentCount: 0,
    );
    final control = ViewNode(
      key: 'fixture-control',
      id: '1',
      kind: 'turn-process',
      target: 'chat',
      anchorSeq: .9,
      location: TurnScopedLocation(turn),
      visible: true,
      data: spec,
      groupTree: 'turn',
    );
    Widget child;
    if (widget.family == 'turn-process') {
      child = parityItem(
        'work-toggle',
        TurnProcessView(
          node: control,
          i18n: i18n,
          controls: TurnProcessControls(
            open: _open,
            foldable: p['mode'] != 'verbose',
            hasContent: p['empty'] != true,
            setOpen: (v) => setState(() => _open = v),
          ),
        ),
      );
    } else if (widget.family == 'work-settings') {
      child = WorkDetailsSettings(preferences: prefs, i18n: i18n);
    } else {
      final names = (p['names'] as List? ?? ['read']).cast<String>();
      final members = <ProcessMember>[];
      for (var i = 0; i < names.length; i++) {
        final args = PartialArguments.fromObject({'path': 'synthetic.txt'});
        final ToolCall call = p['preparing'] == true
            ? PreparingToolCall(
                callId: 'call-$i',
                name: names[i],
                args: args,
                subCalls: const [],
                turn: 1,
                step: 1,
                time: 100 + i,
              )
            : StartedToolCall(
                callId: 'call-$i',
                name: names[i],
                args: args,
                subCalls: const [],
                turn: 1,
                step: 1,
                time: 100 + i,
                argsRaw: '{}',
              );
        members.add(
          ProcessMember(
            ViewNode(
              key: 'fixture-$i',
              id: '$i',
              kind: 'tool-call',
              target: 'chat',
              anchorSeq: 4 + i,
              location: TurnScopedLocation(turn),
              visible: true,
              data: ToolData(call),
            ),
          ),
        );
      }
      child = parityItem(
        'work-toggle',
        ProcessGroupView(
          group: ProcessGroup('fixture-group', 1, members, p['closed'] == true),
          preferences: prefs,
          i18n: i18n,
          open: _open,
          onToggle: () => setState(() => _open = !_open),
          buildMember: (_) => DshChromeText(
            'Synthetic step',
            style: context.dsh
                .textStyle('--dsw-font-s-14')
                .copyWith(height: 24 / 14),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.topLeft,
      child: parityItem(
        'work-el',
        SizedBox(width: (p['width'] as num).toDouble(), child: child),
      ),
    );
  }
}

final Map<String, ParityCase> workDetailsCases = {
  for (final family in ['turn-process', 'work-settings', 'process-group'])
    'chat.$family': ParityCase(
      widgets: const ['dsh_feature_chat:WorkDetails'],
      build: (ctx) => _WorkFixture(ctx, family),
    ),
};
