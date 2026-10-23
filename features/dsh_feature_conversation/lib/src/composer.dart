import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The default composer (dsh `ui-conversation` `InputBar`, phone subset): a
/// growing text field, a send button, and a stop button while a turn runs.
/// Sending while a turn runs queues the message behind it (dsh's default
/// `queue` mode). A takeover occupying the `conversation.composer` chain
/// (approval, a question) replaces this widget while it is pending.
class DefaultComposer extends StatefulWidget {
  const DefaultComposer({super.key, required this.owner, required this.i18n});

  final SessionOwner owner;
  final DshI18n i18n;

  @override
  State<DefaultComposer> createState() => _DefaultComposerState();
}

class _DefaultComposerState extends State<DefaultComposer> {
  final TextEditingController _text = TextEditingController();
  StreamSubscription<SessionSnapshot>? _sub;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sub = widget.owner.session.snapshot.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _text.dispose();
    super.dispose();
  }

  String _a(String key) => widget.i18n.t(appNamespace, key);

  bool get _canSend => _text.text.trim().isNotEmpty && !_sending;

  Future<void> _send() async {
    if (!_canSend) return;
    final text = _text.text.trim();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.owner.actions.send(text);
      if (!mounted) return;
      _text.clear();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = '${_a('session.composer.sendFailed')}: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _cancel() async {
    try {
      await widget.owner.actions.cancel();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final running = widget.owner.session.snapshot.value.running;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DshSpace.lg,
        DshSpace.sm,
        DshSpace.sm,
        DshSpace.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: DshSpace.xs),
              child: Text(
                _error!,
                key: const ValueKey('composer-error'),
                style: theme
                    .textStyle('--dsw-font-xxs-12')
                    .copyWith(
                      color: theme.color('--dsw-alias-state-error-primary'),
                    ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      control: true,
                    ): _send,
                    const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                        _send,
                  },
                  child: DshTextField(
                    controller: _text,
                    placeholder: _a('session.composer.placeholder'),
                    minLines: 1,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                  ),
                ),
              ),
              if (running)
                DshIconButton(
                  key: const ValueKey('composer-cancel'),
                  icon: Icons.stop_rounded,
                  semanticLabel: widget.i18n.t('conversation', 'input.stop'),
                  onPressed: _cancel,
                ),
              if (!running || _canSend)
                DshIconButton(
                  key: const ValueKey('composer-send'),
                  icon: Icons.arrow_upward_rounded,
                  semanticLabel: widget.i18n.t('conversation', 'input.send'),
                  filled: true,
                  onPressed: _canSend ? _send : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
