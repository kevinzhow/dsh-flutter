import 'dart:async';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// The data layer owns reconciliation and caching; the view owns inline
/// projection and leaves every domain action to its keyed contribution.
class ConversationUserText extends StatefulWidget {
  const ConversationUserText({
    super.key,
    required this.owner,
    required this.registry,
    required this.slots,
    this.reportFailure,
  });
  final UserTextOwner owner;
  final UserTextRegistry registry;
  final SlotRegistry slots;
  final void Function(Object)? reportFailure;
  @override
  State<ConversationUserText> createState() => _ConversationUserTextState();
}

class _ConversationUserTextState extends State<ConversationUserText> {
  late UserTextDocument document;
  StreamSubscription<int>? subscription;
  Object? lastError;
  @override
  void initState() {
    super.initState();
    bind();
  }

  void bind() {
    document = widget.registry.createDocument();
    subscription = widget.registry.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(ConversationUserText old) {
    super.didUpdateWidget(old);
    if (old.registry != widget.registry) {
      unawaited(subscription?.cancel());
      bind();
    }
  }

  @override
  void dispose() {
    unawaited(subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final owner = widget.owner;
    List<UserTextNode>? nodes;
    try {
      nodes = document.evaluate(owner.text, facts: owner.facts);
      lastError = null;
    } on Object catch (e) {
      if (!identical(lastError, e)) {
        lastError = e;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.reportFailure?.call(e);
        });
      }
    }
    final spans = nodes == null
        ? <InlineSpan>[TextSpan(text: owner.text)]
        : [
            for (final node in nodes)
              widget.slots.renderKeyed(
                    DshSlots.conversationUserTextNode
                        .typed<UserTextNodeOwner, InlineSpan>(),
                    node.id,
                    UserTextNodeOwner(
                      node: node,
                      raw: node.raw(owner.text),
                      interactive: owner.interactive,
                      ellipsis: owner.ellipsis,
                      session: owner.session,
                    ),
                  ) ??
                  TextSpan(
                    text: node.id == 'text'
                        ? node.data['display'] as String? ??
                              node.raw(owner.text)
                        : node.raw(owner.text),
                  ),
          ];
    return Text.rich(
      TextSpan(children: spans),
      maxLines: owner.ellipsis ? 1 : null,
      softWrap: !owner.ellipsis,
      overflow: owner.ellipsis ? TextOverflow.ellipsis : TextOverflow.clip,
    );
  }
}

void registerUserTextFactory(
  SlotRegistry slots,
  UserTextRegistry registry, {
  void Function(Object)? reportFailure,
}) {
  slots.register<UserTextOwner, Widget>(
    DshSlots.conversationUserText.typed<UserTextOwner, Widget>(),
    (owner) => ConversationUserText(
      owner: owner,
      registry: registry,
      slots: slots,
      reportFailure:
          reportFailure ??
          (error) => FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              library: 'conversation.user.text',
            ),
          ),
    ),
  );
  slots.register<UserTextNodeOwner, InlineSpan>(
    DshSlots.conversationUserTextNode.typed<UserTextNodeOwner, InlineSpan>(),
    (owner) => WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: DshReferenceChip(
        key: ValueKey(owner.identity),
        appearance: 'session',
        label: owner.node.data['label'] as String,
        title: owner.raw,
      ),
    ),
    key: 'session',
  );
  slots.register<UserTextNodeOwner, InlineSpan>(
    DshSlots.conversationUserTextNode.typed<UserTextNodeOwner, InlineSpan>(),
    (owner) =>
        TextSpan(text: owner.node.data['display'] as String? ?? owner.raw),
    key: 'text',
  );
}
