import 'dart:async';

import 'package:dsh_client/dsh_client.dart' show ConnectionState;
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart' hide ConnectionState;

import '../app_controller.dart';

/// The connection feedback of a screen that shows live sessions.
///
/// dsh web's own part is the inline [DshConnectionIndicator] (Reconnecting
/// with its dots while an attempt is in flight, Disconnected between attempts,
/// Connected for two seconds once it is back; tapping retries now), shown only
/// while something is wrong. Whalee adds what the web client has no need for:
/// the retry number and countdown beside it, and a card for the three
/// situations that need the user: the host is not reachable at all, the host
/// restarted (the launch token is no longer valid: pair again), and the host's
/// certificate is not the trusted one.
class ConnectionBar extends StatefulWidget {
  const ConnectionBar({super.key, required this.controller});

  final AppController controller;

  @override
  State<ConnectionBar> createState() => _ConnectionBarState();
}

class _ConnectionBarState extends State<ConnectionBar> {
  Timer? _tick;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(ConnectionBar old) {
    super.didUpdateWidget(old);
    if (old.controller != c) {
      old.controller.removeListener(_sync);
      c.addListener(_sync);
    }
  }

  @override
  void dispose() {
    c.removeListener(_sync);
    _tick?.cancel();
    super.dispose();
  }

  /// A one-second tick runs only while a retry countdown is on screen.
  void _sync() {
    final counting = c.status.state == ConnectionState.waiting;
    if (counting && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!counting) {
      _tick?.cancel();
      _tick = null;
    }
    if (mounted) setState(() {});
  }

  DshConnectionIndicatorState? get _indicator {
    if (c.phase != ConnectionPhase.connected && !c.reconnecting) return null;
    final state = c.status.state;
    if (c.reconnecting) {
      return state == ConnectionState.waiting
          ? DshConnectionIndicatorState.disconnected
          : DshConnectionIndicatorState.connecting;
    }
    return c.recovered ? DshConnectionIndicatorState.recovered : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final i18n = c.i18n;
    String s(String key) => i18n.t('settings', key);
    String a(String key, [Map<String, Object?> params = const {}]) =>
        i18n.t(appNamespace, key, params: params);
    final status = c.status;
    final indicator = _indicator;
    final host = c.hostOrigin ?? '';

    String? retryText;
    if (indicator != null && status.attempt > 0) {
      if (status.state == ConnectionState.waiting && status.retryAt != null) {
        final left = status.retryAt!.difference(DateTime.now());
        final seconds = (left.inMilliseconds / 1000).ceil().clamp(0, 99);
        retryText = a('connection.retry', {
          'n': status.attempt,
          'seconds': seconds,
        });
      } else {
        retryText = a('connection.retrying', {'n': status.attempt});
      }
    }

    Widget? card;
    if (status.state == ConnectionState.needsPairing) {
      card = _Card(
        key: const ValueKey('connection-needs-pairing'),
        title: a('connection.needsPairing.title'),
        body: a('connection.needsPairing.body'),
        action: DshButton(
          key: const ValueKey('connection-repair'),
          variant: DshButtonVariant.primary,
          size: DshButtonSize.sm,
          onPressed: c.openRepair,
          child: Text(a('connection.repair')),
        ),
      );
    } else if (status.state == ConnectionState.certificateRefused) {
      card = _Card(
        key: const ValueKey('connection-certificate'),
        title: a('connection.certificate.title'),
        body: a('connection.certificate.body'),
        action: DshButton(
          key: const ValueKey('connection-certificate-review'),
          variant: DshButtonVariant.primary,
          size: DshButtonSize.sm,
          onPressed: c.reviewRefusedCertificate,
          child: Text(a('connection.certificate.review')),
        ),
      );
    } else if (status.unreachable && c.reconnecting) {
      card = _Card(
        key: const ValueKey('connection-unreachable'),
        title: a('connection.unreachable.title'),
        body: a('connection.unreachable.body', {'host': host}),
        action: DshButton(
          key: const ValueKey('connection-retry-now'),
          variant: DshButtonVariant.outline,
          size: DshButtonSize.sm,
          onPressed: c.reconnectNow,
          child: Text(a('connection.retryNow')),
        ),
      );
    }

    if (indicator == null && card == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DshSpace.lg,
        vertical: DshSpace.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (indicator != null)
            Row(
              key: const ValueKey('connection-indicator-row'),
              children: [
                DshConnectionIndicator(
                  state: indicator,
                  disconnectedLabel: s('connection.error'),
                  connectingLabel: s('connection.connecting'),
                  recoveredLabel: s('connection.connected'),
                  reconnectActionLabel: s('connection.reconnect'),
                  restartActionLabel: s('connection.restart'),
                  onReconnect: c.reconnectNow,
                ),
                if (retryText != null) ...[
                  const SizedBox(width: DshSpace.sm),
                  Flexible(
                    child: Text(
                      retryText,
                      key: const ValueKey('connection-retry-text'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme
                          .textStyle('--dsw-font-xxs-12')
                          .copyWith(color: theme.labelSecondary),
                    ),
                  ),
                ],
              ],
            ),
          if (card != null) ...[
            if (indicator != null) const SizedBox(height: DshSpace.xs),
            card,
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.title,
    required this.body,
    required this.action,
  });

  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return DshContainer(
      padding: const EdgeInsets.all(DshSpace.md),
      decoration: BoxDecoration(
        color: theme.color('--dsw-alias-state-warn-tertiary'),
        borderRadius: BorderRadius.circular(theme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme
                .textStyle('--dsw-font-s-strong-14')
                .copyWith(color: theme.labelPrimary),
          ),
          const SizedBox(height: DshSpace.xs),
          Text(
            body,
            style: theme
                .textStyle('--dsw-font-xxs-12')
                .copyWith(color: theme.labelSecondary),
          ),
          const SizedBox(height: DshSpace.sm),
          action,
        ],
      ),
    );
  }
}
