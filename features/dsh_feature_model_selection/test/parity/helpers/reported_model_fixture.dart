// A synthetic caller-owned Host, rendered by the actual production ModelSeat.
// This helper intentionally depends on neither flutter_test nor dsh_parity.
import 'dart:async';

import 'package:dsh_client/generated.dart' as session;
import 'package:dsh_feature_model_selection/dsh_feature_model_selection.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

const reportedModelGroups = [
  {
    'id': 'deepseek-official',
    'name': 'DeepSeek',
    'models': [
      {
        'id': 'flash',
        'name': 'DeepSeek V4.1 Flash',
        'reasoning': {
          'efforts': [
            {'id': 'low', 'name': 'Low'},
            {'id': 'high', 'name': 'High'},
            {'id': 'max', 'name': 'Max'},
          ],
          'defaultEffort': 'high',
        },
      },
      {'id': 'pro', 'name': 'DeepSeek V4.1 Pro'},
    ],
  },
  {
    'id': 'local',
    'name': 'Local provider',
    'models': [
      {'id': 'alpha', 'name': 'Alpha'},
      {'id': 'beta', 'name': 'Beta'},
      {'id': 'gamma', 'name': 'Gamma'},
      {'id': 'delta', 'name': 'Delta'},
    ],
  },
];

class ReportedModelFixture extends StatefulWidget {
  const ReportedModelFixture({
    super.key,
    required this.i18n,
    this.groups = reportedModelGroups,
  });
  final DshI18n i18n;
  final List<Map<String, Object?>> groups;
  @override
  State<ReportedModelFixture> createState() => _ReportedModelFixtureState();
}

class _ReportedModelFixtureState extends State<ReportedModelFixture> {
  final _host = FakeHost(), _projections = ProjectionStore();
  late final _catalog = ModelCatalogDirectory(_host.remotes);
  late final _directory = ModelDirectory(
    remotes: _host.remotes,
    sessionId: 'reported-model',
    catalog: _catalog,
    projections: _projections,
  );
  var _seq = 1;
  String _result = 'none';

  @override
  void initState() {
    super.initState();
    const initial = {
      'provider': 'deepseek-official',
      'model': 'flash',
      'reasoningEffort': 'max',
    };
    _host.handlers['session/modelCatalog'] = (_) => {
      'default': initial,
      'routableProviders': [for (final group in widget.groups) group['id']],
      'groups': widget.groups,
      'failures': <Object>[],
    };
    _host.handlers['session/selectModel'] = (args) {
      final request = Map<String, Object?>.from(args['request']! as Map);
      final selected = {
        for (final entry in request.entries)
          if (entry.key != 'sessionId') entry.key: entry.value,
      };
      _projections.apply('modelSelection', {
        'lastUsed': null,
        'next': selected,
      }, ++_seq);
      if (mounted) {
        setState(
          () => _result =
              '${selected['provider']}/${selected['model']}/${selected['reasoningEffort'] ?? 'default'}',
        );
      }
      return {'selected': selected};
    };
    _directory.state.set(
      ModelDirectoryState(
        status: ModelDirectoryStatus.ready,
        groups: [
          for (final group in widget.groups)
            session.ModelProviderGroup.fromJson(group),
        ],
        current: session.ModelSelection.fromJson(initial),
      ),
    );
    _projections.apply('modelSelection', {
      'lastUsed': null,
      'next': initial,
    }, _seq);
    unawaited(_directory.load());
  }

  @override
  void dispose() {
    unawaited(() async {
      await _directory.dispose();
      await _catalog.dispose();
      await _host.close();
    }());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        right: 24,
        bottom: 24,
        child: ModelSeat(directory: _directory, i18n: widget.i18n),
      ),
      Positioned(
        left: 24,
        top: 24,
        child: DshChromeText(
          'Selection: $_result',
          key: const ValueKey('reported-model-result'),
          style: context.dsh.textStyle('--dsw-font-xs-13'),
        ),
      ),
    ],
  );
}
