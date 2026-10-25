// Synthetic native component replay. No host, credentials or real conversations.
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_feature_user_questions/dsh_feature_user_questions.dart';
import 'package:dsh_feature_workflow_run/dsh_feature_workflow_run.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_flutter/src/platform/window_chrome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadPinnedFontsFromEnvironment();
  await WindowChrome.init();
  final dark =
      const bool.fromEnvironment('PARITY_DARK') ||
      Platform.environment['WHALEE_PLATFORM_BRIGHTNESS'] == 'dark';
  final zh =
      const String.fromEnvironment('PARITY_LOCALE') == 'zh' ||
      (Platform.environment['LC_ALL'] ?? '').startsWith('zh');
  final brightness = dark ? Brightness.dark : Brightness.light;
  final theme = resolveTheme(officialPack, ThemeSettings(), brightness);
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: brightness, extensions: [theme]),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
        backgroundColor: theme.bgBase,
        body: SafeArea(
          child: _Fixture(DshI18n(zh ? DshLocale.zh : DshLocale.en)),
        ),
      ),
    ),
  );
}

class _Fixture extends StatefulWidget {
  const _Fixture(this.i18n);
  final DshI18n i18n;
  @override
  State<_Fixture> createState() => _FixtureState();
}

class _FixtureState extends State<_Fixture> {
  int tab = 1;
  WorkflowRunStatus status = WorkflowRunStatus.running;
  String? opened;
  static const tabs = ['Goal', 'Reply', 'Context', 'Workflow'];
  @override
  Widget build(BuildContext context) {
    final i18n = widget.i18n;
    final child = switch (tab) {
      0 => GoalCommandInputView(
        data: const CommandInputData(
          commandId: 'goal-fixture',
          text: '/goal Ship a synthetic fixture and keep /goal mentions plain.',
          time: 0,
        ),
        i18n: i18n,
      ),
      1 => QuestionReplyView(
        data: const QuestionReplyData(
          callId: 'ask-fixture',
          text: 'Synthetic reply',
          time: 0,
          questions: [
            {
              'id': 'q',
              'header': 'Choice',
              'question': 'Which option?',
              'detail': 'Pick a synthetic fixture',
              'options': [
                {'label': 'One', 'description': 'First option'},
                {'label': 'Two'},
              ],
            },
            {'id': 'extra', 'question': 'Any extras?'},
          ],
          answers: [
            {
              'id': 'q',
              'selected': ['One'],
              'custom': 'Extra',
            },
          ],
        ),
        i18n: i18n,
      ),
      2 => ContextInjectionView(
        data: MessageData(
          kind: 'context',
          seq: 1,
          time: 0,
          form: 'notice',
          producerRole: 'context',
          producerLabel: 'Fixture',
          source: const {
            'kind': 'fixture',
            'form': 'notice',
            'summary': 'Synthetic notice',
          },
          content: [
            {
              'type': 'text',
              'text': List.generate(
                40,
                (i) => 'Synthetic context line $i',
              ).join('\n'),
            },
          ],
        ),
        i18n: i18n,
      ),
      _ => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          WorkflowRunPanel(
            data: WorkflowRunData(
              name: 'Synthetic workflow',
              status: status,
              phases: [
                WorkflowRunPhase('Read', [
                  WorkflowRunMember(
                    seq: 1,
                    label: 'Read fixture files',
                    childId: 'child-a',
                    status: status,
                  ),
                  const WorkflowRunMember(
                    seq: 2,
                    label: 'Compare results',
                    childId: 'child-b',
                    status: WorkflowRunStatus.completed,
                  ),
                ]),
              ],
            ),
            i18n: i18n,
            canOpen: (m) => m.status == WorkflowRunStatus.running,
            onOpen: (m) => setState(() => opened = m.childId),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final next in [
                WorkflowRunStatus.completed,
                WorkflowRunStatus.running,
                WorkflowRunStatus.failed,
              ])
                Expanded(
                  child: DshButton(
                    onPressed: () => setState(() {
                      FocusManager.instance.primaryFocus?.unfocus();
                      status = next;
                      opened = null;
                    }),
                    child: Text(next.name),
                  ),
                ),
            ],
          ),
          if (opened != null) Text('Opened synthetic member: $opened'),
        ],
      ),
    };
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: DshButton(
                    onPressed: () => setState(() {
                      tab = i;
                      opened = null;
                    }),
                    child: Text(tabs[i]),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: math.min(748, constraints.maxWidth - 40),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: KeyedSubtree(key: ValueKey(tab), child: child),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
