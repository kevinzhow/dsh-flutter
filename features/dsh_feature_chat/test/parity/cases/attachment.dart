// The file cards of a sent message (dsh ui-chat UserContent), through the chat feature's real user bubble:
// attachments only, so no text bubble. Props are the React host's `attachment.sent` input
// (tool/parity-ext/build-attachment.py): {layout, files: [{name, bytes}]}.
import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';

final Map<String, ParityCase> sentAttachmentCases = {
  'attachment.sent': ParityCase(
    widgets: const ['dsh_feature_chat:UserBubble', 'dsh_ui:DshMessageFileCard'],
    build: (ctx) => ParityStack(
      layout: ctx.layout,
      children: [
        UserBubble(
          text: '',
          i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
          attachments: [
            for (final f
                in (ctx.props['files'] as List).cast<Map<String, dynamic>>())
              UserFileView(
                name: f['name'] as String,
                bytes: (f['bytes'] as num).toInt(),
              ),
          ],
        ),
      ],
    ),
  ),
};
