import 'package:dsh_feature_conversation/dsh_feature_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show Material, MaterialType;

final Map<String, ParityCase> queueCases = {
  'conversation.queue': ParityCase(
    widgets: const ['dsh_feature_conversation:QueuePanel'],
    build: (ctx) => Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: (ctx.props['width'] as num).toDouble(),
        child: QueuePanel(
          rows: [
            for (final raw in ctx.props['rows'] as List)
              InboxItem.tryParse(Map<String, Object?>.from(raw as Map))!,
          ],
          pending: [
            for (final p in ctx.props['pending'] as List? ?? [])
              PendingSubmission(
                p['requestId'] as String,
                p['text'] as String,
                DateTime(2026),
              ),
          ],
          running: ctx.props['running'] != false,
          mutable: ctx.props['mutable'] != false,
          i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
          updateQueue: (_, _) async {},
        ),
      ),
    ),
  ),
  'conversation.enter-setting': ParityCase(
    widgets: const ['dsh_feature_conversation:EnterBehaviorSettings'],
    build: (ctx) => SizedBox(
      width: (ctx.props['width'] as num).toDouble(),
      child: EnterBehaviorSettings(
        preferences: ConversationPreferences()
          ..setBusyEnter(ctx.props['value'] as String),
        i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
      ),
    ),
  ),
};
