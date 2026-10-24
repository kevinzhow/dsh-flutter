import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart' show HostRemotes;

import 'reference_source.dart';

/// Register the unified `@` file and session source into the trigger pipeline.
/// Returns the disposer.
void Function() registerReferenceFeature({
  required InputTriggerRegistry triggers,
  required HostRemotes remotes,
  required InputSessionPort sessions,
  required DshI18n Function() i18n,
}) => triggers.registerSource(
  ReferenceSource(
    files: remotes.fileReferences,
    sessionReferences: remotes.sessionReferences,
    sessions: sessions,
    i18n: i18n,
  ),
);
