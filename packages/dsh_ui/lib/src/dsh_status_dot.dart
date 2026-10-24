import 'package:flutter/widgets.dart';

import 'dsh_snapped_box.dart';
import 'theme_access.dart';

/// Status vocabulary of rows and cards.
enum DshStatus { idle, running, success, error, warn }

/// A small filled dot in the colour of a [DshStatus].
class DshStatusDot extends StatelessWidget {
  const DshStatusDot(this.status, {super.key, this.size = 8});

  final DshStatus status;
  final double size;

  /// The theme token that colours [status].
  static String tokenOf(DshStatus status) => switch (status) {
    DshStatus.idle => '--dsw-alias-state-idle-primary',
    DshStatus.running => '--dsw-alias-state-business-primary',
    DshStatus.success => '--dsw-alias-state-success-primary',
    DshStatus.error => '--dsw-alias-state-error-primary',
    DshStatus.warn => '--dsw-alias-state-warn-primary',
  };

  @override
  Widget build(BuildContext context) => DshContainer(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: context.dsh.color(tokenOf(status)),
      shape: BoxShape.circle,
    ),
  );
}
