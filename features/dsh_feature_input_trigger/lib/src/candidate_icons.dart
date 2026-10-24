import 'package:dsh_ui/dsh_ui.dart';

/// The glyph of a candidate's `icon` key. dsh passes either a reference glyph
/// token (`file`, `folder`, `session`) or an icon component; the pure pipeline
/// carries the key and the menu maps it here.
DshIconData? candidateIcon(String? key) => switch (key) {
  'file' => DshIcons.browse,
  'folder' => DshIcons.folderClose,
  'session' => DshIcons.chatLines,
  'goal' => DshIcons.goal,
  'plan' => DshIcons.plan,
  'feedback' => DshIcons.paperPlane,
  'compact' => DshIcons.compact,
  'permission' => DshIcons.permissionFullAccess,
  'export' => DshIcons.download,
  'model' => DshIcons.data,
  'paperclip' => DshIcons.paperclip,
  _ => null,
};
