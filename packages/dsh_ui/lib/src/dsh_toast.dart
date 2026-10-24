import 'dart:async';

import 'package:flutter/widgets.dart';

import 'dsh_icon.dart';
import 'dsh_icons.g.dart';
import 'dsh_snapped_box.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

/// Hold at full opacity before the fade (dsh `Toast` `HOLD_MS`).
const Duration dshToastHold = Duration(milliseconds: 3000);

/// The fade (dsh `FADE_MS`).
const Duration dshToastFade = Duration(milliseconds: 1000);

/// The floating banner of dsh's `Toast`: 40px below the top, centred, dark in
/// both themes, click-through, with a warning-tinted icon seat. It lives for
/// [dshToastHold] plus [dshToastFade], then calls [onDone].
class DshToast extends StatefulWidget {
  const DshToast({
    super.key,
    required this.text,
    this.hold = dshToastHold,
    required this.onDone,
  });

  final String text;
  final Duration hold;
  final VoidCallback onDone;

  @override
  State<DshToast> createState() => _DshToastState();
}

class _DshToastState extends State<DshToast> with TickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  )..forward();
  late final AnimationController _out = AnimationController(
    vsync: this,
    duration: dshToastFade,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.hold, () {
      if (!mounted) return;
      unawaited(
        _out.forward().whenComplete(() {
          if (mounted) widget.onDone();
        }),
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _in.dispose();
    _out.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 40, left: 24, right: 24),
          child: AnimatedBuilder(
            animation: Listenable.merge([_in, _out]),
            builder: (context, child) => Opacity(
              opacity: _in.value * (1 - _out.value),
              child: Transform.translate(
                offset: Offset(0, -6 * (1 - _in.value)),
                child: child,
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Semantics(
                liveRegion: true,
                child: DshContainer(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: theme.color('--dsw-alias-toast-bg'),
                    borderRadius: BorderRadius.circular(theme.radiusLg),
                    boxShadow: theme.boxShadow('--dsw-shadow-lv3'),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DshIcon(
                        DshIcons.warning,
                        size: 16,
                        color: theme.color('--dsw-alias-state-warn-label'),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: DshChromeText(
                          widget.text,
                          style: theme
                              .textStyle('--dsw-font-s-14')
                              .copyWith(
                                color: theme.color('--dsw-alias-toast-label'),
                                height: 22 / 14,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Show one [DshToast] over the app and replace a banner still showing from the
/// same [DshToasts] (announcing again replays it).
class DshToasts {
  OverlayEntry? _entry;

  void show(BuildContext context, String text) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay != null) showOn(overlay, text);
  }

  void showOn(OverlayState overlay, String text) {
    dismiss();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => DshToast(
        key: UniqueKey(),
        text: text,
        onDone: () {
          if (_entry == entry) _entry = null;
          entry.remove();
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  void dismiss() {
    _entry?.remove();
    _entry = null;
  }
}
