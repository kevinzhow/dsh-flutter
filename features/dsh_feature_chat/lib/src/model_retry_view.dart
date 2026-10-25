import 'dart:async';
import 'dart:math' as math;

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The pinned Web client's retry counter never displays zero while waiting
/// for the producer's retry-started event.
int modelRetrySeconds(num milliseconds) =>
    math.max(1, (milliseconds / 1000).ceil());

/// DSH MessageItem's retry disclosure, with a locally anchored countdown.
class ModelRetryView extends StatefulWidget {
  const ModelRetryView({
    super.key,
    required this.attempt,
    required this.i18n,
    this.initiallyOpen = false,
    this.now,
  });
  final ModelRetryAttempt attempt;
  final DshI18n i18n;
  final bool initiallyOpen;
  @visibleForTesting
  final DateTime Function()? now;

  @override
  State<ModelRetryView> createState() => _ModelRetryViewState();
}

class _ModelRetryViewState extends State<ModelRetryView> {
  Timer? _timer;
  late DateTime _deadline;
  late int _seconds;
  late bool _open = widget.initiallyOpen;
  bool _hover = false, _focused = false;
  bool get _active => widget.attempt.state == ModelRetryState.scheduled;
  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _resetDeadline();
    _schedule();
  }

  void _resetDeadline() {
    // Host time is deliberately ignored: the host and client clocks can differ.
    _deadline = _now().add(
      Duration(microseconds: (widget.attempt.delayMs * 1000).round()),
    );
    _seconds = modelRetrySeconds(_deadline.difference(_now()).inMilliseconds);
  }

  void _schedule() {
    _timer?.cancel();
    if (!_active || _seconds == 1) return;
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final next = modelRetrySeconds(
        _deadline.difference(_now()).inMilliseconds,
      );
      if (next != _seconds) setState(() => _seconds = next);
      if (next == 1) _timer?.cancel();
    });
  }

  @override
  void didUpdateWidget(ModelRetryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.attempt.seq != widget.attempt.seq ||
        oldWidget.attempt.delayMs != widget.attempt.delayMs;
    if (changed) _resetDeadline();
    if (changed || oldWidget.attempt.state != widget.attempt.state) _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _t(String key, {Map<String, Object?> params = const {}}) =>
      widget.i18n.t('chat', key, params: params);
  void _toggle() => setState(() => _open = !_open);

  String get _failure {
    final key = switch (widget.attempt.failureCode) {
      'ACCOUNT_SIGNED_OUT' => 'message.failure.accountSignedOut',
      'INTERRUPTED' => 'message.failure.interrupted',
      'ACCOUNT_SIGN_IN_REQUIRED' => 'message.failure.accountSignInRequired',
      'QUOTA' || 'ACCOUNT_QUOTA' => 'message.failure.quota',
      'AUTH' => 'message.failure.auth',
      _ => null,
    };
    return key == null ? widget.attempt.failureMessage : _t(key);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final attempt = widget.attempt;
    final chevronBorder = dshBorderWidthOf(context, 1.5);
    final label = _t(switch (attempt.state) {
      ModelRetryState.scheduled => 'message.retry.active',
      ModelRetryState.started => 'message.retry.started',
      ModelRetryState.cancelled => 'message.retry.cancelled',
    });
    final status = _t(
      'message.retry.status',
      params: {
        'label': label,
        'retry': attempt.retry,
        'maximum': attempt.maxRetries ?? '∞',
        'seconds': _active ? _seconds : modelRetrySeconds(attempt.delayMs),
      },
    );
    final color = _hover
        ? theme.labelSecondary
        : theme.color('--dsw-alias-label-tertiary');
    final style = theme
        .textStyle('--dsw-font-xs-13')
        .copyWith(color: color, height: 20 / 13);
    return Column(
      key: const ValueKey('model-retry'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          liveRegion: true,
          child: FocusableActionDetector(
            mouseCursor: SystemMouseCursors.click,
            onShowHoverHighlight: (value) => setState(() => _hover = value),
            onShowFocusHighlight: (value) => setState(() => _focused = value),
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            },
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  _toggle();
                  return null;
                },
              ),
            },
            child: GestureDetector(
              key: const ValueKey('model-retry-summary'),
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              child: DshDecoratedBox(
                decoration: theme.cornerDecoration(
                  theme.radiusSm,
                  borderColor: _focused ? theme.focusRingColor : null,
                  borderWidth: _focused ? chevronBorder : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: DshShimmer(
                          active: _active,
                          child: DshChromeText(status, style: style),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: SizedBox(
                          width: 6 + chevronBorder,
                          height: 6 + chevronBorder,
                          child: CustomPaint(
                            painter: _RetryChevron(color, _open, chevronBorder),
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
        if (_open)
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detail(
                  context,
                  _t('message.retry.delay'),
                  _t(
                    'duration.milliseconds',
                    params: {'milliseconds': attempt.delayMs.round()},
                  ),
                  localizedDuration: true,
                ),
                const SizedBox(height: 2),
                _detail(context, _t('message.retry.failure'), _failure),
              ],
            ),
          ),
      ],
    );
  }

  Widget _detail(
    BuildContext context,
    String label,
    String value, {
    bool localizedDuration = false,
  }) {
    final theme = context.dsh;
    final style = theme
        .textStyle('--dsw-font-xs-13')
        .copyWith(
          height: 18 / 13,
          color: theme.color('--dsw-alias-label-tertiary'),
        );
    // Blink's text-autospace:normal inserts 1/8ic between the numeric
    // duration and its Chinese unit (2500毫秒). Pinned Noto CJK is full-em.
    // Keep the translated string intact for accessibility/copy semantics.
    final duration = localizedDuration
        ? RegExp(r'^([0-9]+)([\u3400-\u9fff].*)$').firstMatch(value)
        : null;
    return DshChromeBaseline(
      style: style,
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            TextSpan(
              text: label,
              style: TextStyle(color: theme.labelSecondary),
            ),
            if (duration == null)
              TextSpan(text: value)
            else ...[
              TextSpan(text: duration.group(1)),
              WidgetSpan(
                child: SizedBox(
                  key: const ValueKey('model-retry-duration-autospace'),
                  width:
                      MediaQuery.textScalerOf(context).scale(style.fontSize!) /
                      8,
                ),
              ),
              TextSpan(text: duration.group(2)),
            ],
          ],
        ),
        strutStyle: dshStrut(style),
        semanticsLabel: '$label$value',
      ),
    );
  }
}

/// The Web retry summary's 6px CSS border chevron (no icon-font dependency).
class _RetryChevron extends CustomPainter {
  _RetryChevron(this.color, this.open, this.borderWidth);
  final Color color;
  final bool open;
  final double borderWidth;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(open ? math.pi / 4 : -math.pi / 4);
    canvas.translate(-size.width / 2, -size.height / 2);
    canvas.drawPath(
      Path()
        ..moveTo(size.width - borderWidth / 2, 0)
        ..lineTo(size.width - borderWidth / 2, size.height - borderWidth / 2)
        ..lineTo(0, size.height - borderWidth / 2),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );
  }

  @override
  bool shouldRepaint(_RetryChevron old) =>
      old.color != color || old.open != open || old.borderWidth != borderWidth;
}
