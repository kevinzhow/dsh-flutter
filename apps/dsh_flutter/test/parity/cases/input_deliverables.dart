import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_deliverables/dsh_feature_deliverables.dart';
import 'package:dsh_feature_secret_mask/dsh_feature_secret_mask.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import '../helpers/deliverables_fixture.dart';

final Map<String, ParityCase> inputDeliverablesCases = {
  for (final family in ['reference', 'secret', 'card', 'changes', 'diff'])
    'input-deliverables.$family': ParityCase(
      widgets: ['dsh_feature_deliverables:$family'],
      build: (ctx) => _Surface(
        family: family,
        name: ctx.props['name'] as String,
        width: (ctx.props['width'] as num).toDouble(),
        i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
      ),
    ),
};

class _Surface extends StatefulWidget {
  const _Surface({
    required this.family,
    required this.name,
    required this.width,
    required this.i18n,
  });
  final String family, name;
  final double width;
  final DshI18n i18n;
  @override
  State<_Surface> createState() => _SurfaceState();
}

class _SurfaceState extends State<_Surface> {
  final model = DeliverablesModel(SyntheticDeliverables()),
      owner = testSessionOwner('fixture'),
      slots = SlotRegistry();
  @override
  void initState() {
    super.initState();
    for (final slot in DshSlots.all) {
      slots.declare(slot);
    }
  }

  @override
  void dispose() {
    unawaited(model.dispose());
    unawaited(owner.conversation.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.name;
    Widget body;
    switch (widget.family) {
      case 'reference':
        final appearance = name == 'long' ? 'file' : name,
            label = name == 'long'
                ? 'a very long synthetic file name with multiple words.dart'
                : name == 'session'
                ? 'Synthetic session'
                : name == 'folder'
                ? 'documents'
                : 'report.dart';
        body = DefaultTextStyle(
          style: context.dsh
              .textStyle('--dsw-font-s-14')
              .sized(14, line: 22)
              .copyWith(color: context.dsh.labelPrimary),
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Read '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: DshReferenceChip(
                    appearance: appearance,
                    label: label,
                    title: label,
                  ),
                ),
                const TextSpan(text: ' for this synthetic task.'),
              ],
            ),
          ),
        );
      case 'secret':
        final raw = name == 'block'
            ? '-----BEGIN PRIVATE KEY-----\nSynthetic only\n-----END PRIVATE KEY-----'
            : 'sk-${List.filled(16, 'Q7').join()}';
        final node = CredentialScanner().match(raw, 0)!;
        body = DefaultTextStyle(
          style: context.dsh
              .textStyle('--dsw-font-s-14')
              .sized(14, line: 22)
              .copyWith(color: context.dsh.labelPrimary),
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Use '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: SecretText(
                    raw: raw,
                    masked: node.data['masked'] as String,
                    interactive: name != 'readonly',
                    i18n: widget.i18n,
                  ),
                ),
                const TextSpan(text: ' safely.'),
              ],
            ),
          ),
        );
      case 'card':
        if (name != 'ready') {
          model.phases.set({
            const DeliveryFile('fixture', 8, 0).actionKey: NativeOpenPhase
                .values
                .byName(name),
          });
        }
        body = Padding(
          padding: EdgeInsets.zero,
          child: PresentedFileCard(
            file: const PresentedPath(
              seq: 8,
              index: 0,
              path: '/synthetic/report.md',
              description: 'Synthetic report (Markdown)',
            ),
            owner: owner,
            model: model,
            slots: slots,
            i18n: widget.i18n,
            onPreview: () {},
          ),
        );
      case 'changes':
        final count = name == 'single' ? 1 : 5;
        body = Padding(
          padding: EdgeInsets.zero,
          child: ChangedFilesCard(
            summary: ChangesSummary(
              turn: 1,
              total: count,
              added: count,
              deleted: 1,
              files: [
                for (var i = 0; i < count; i++)
                  ChangedFile(
                    path: '/synthetic/file$i.dart',
                    display: 'file$i.dart',
                    added: 1,
                    deleted: i == 0 ? 1 : 0,
                  ),
              ],
            ),
            seq: 7,
            sessionId: 'fixture',
            model: model,
            i18n: widget.i18n,
            onReview: (_) {},
          ),
        );
      default:
        final state = name == 'missing' || name == 'error'
            ? HostRead<ChangesDiff>(HostReadPhase.values.byName(name))
            : HostRead(
                HostReadPhase.ready,
                ChangesDiff(
                  kind: name == 'binary' || name == 'oversized' ? name : 'text',
                  path: '/synthetic/report.dart',
                  display: 'report.dart',
                  before: true,
                  after: true,
                  hunks: syntheticDeliveryHunks,
                ),
              );
        body = DeliverablesFileDiff(
          state: state,
          split: name == 'split',
          wrap: name == 'wrap',
          i18n: widget.i18n,
          retry: () {},
        );
    }
    return Align(
      alignment: Alignment.topLeft,
      child: parityItem(
        'input-deliverables-surface',
        SizedBox(width: widget.width, child: body),
      ),
    );
  }
}
