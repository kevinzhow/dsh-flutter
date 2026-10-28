// The production model sheet with a synthetic, caller-owned directory state.
import 'dart:async';

import 'package:dsh_client/generated.dart' as session;
import 'package:dsh_feature_model_selection/dsh_feature_model_selection.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:flutter/material.dart' show Material;
import 'package:flutter/widgets.dart';

class _ModelFixture extends StatefulWidget {
  const _ModelFixture({required this.props, required this.locale});
  final Map<String, dynamic> props;
  final String locale;

  @override
  State<_ModelFixture> createState() => _ModelFixtureState();
}

class _ModelFixtureState extends State<_ModelFixture> {
  final host = FakeHost();
  late final catalog = ModelCatalogDirectory(host.remotes);
  late final directory = ModelDirectory(
    remotes: host.remotes,
    sessionId: 'parity',
    catalog: catalog,
    projections: ProjectionStore(),
  );

  @override
  void initState() {
    super.initState();
    directory.state.set(
      ModelDirectoryState(
        status: ModelDirectoryStatus.ready,
        groups: [
          for (final raw
              in (widget.props['groups'] as List).cast<Map<String, dynamic>>())
            session.ModelProviderGroup.fromJson(raw),
        ],
      ),
    );
  }

  @override
  void dispose() {
    unawaited(() async {
      await directory.dispose();
      await catalog.dispose();
      await host.close();
    }());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomLeft,
    child: SizedBox(
      width: (widget.props['width'] as num).toDouble(),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: ModelSheet(
          directory: directory,
          i18n: DshI18n(DshLocale.fromTag(widget.locale)),
        ),
      ),
    ),
  );
}

final Map<String, ParityCase> menuStickyModelCases = {
  'menu-sticky.model': ParityCase(
    widgets: const ['dsh_feature_model_selection:ModelSheet'],
    framed: false,
    build: (ctx) => Material(
      color: ctx.theme.bgBase,
      child: _ModelFixture(props: ctx.props, locale: ctx.locale),
    ),
  ),
};
