import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Copy-to-clipboard with a one second "Copied" confirmation (dsh
/// `useCopyFeedback`).
mixin DshCopyFeedback<T extends StatefulWidget> on State<T> {
  bool copied = false;
  Timer? _timer;

  Future<void> copyText(String text) async {
    if (copied) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => copied = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
