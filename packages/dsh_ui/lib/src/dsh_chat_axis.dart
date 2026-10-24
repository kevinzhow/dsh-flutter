import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// From this window width the app follows dsh's desktop layout (draggable
/// scrollbar, list-wide selection); below it the phone adaptations apply
/// (768 is the cut raft-flutter's presentation policy uses for compact windows).
const double dshWideLayoutWidth = 768;

/// dsh's shared width axis of the active conversation: the message column, the
/// dock cards and the composer card all hang off one content width.
///
/// Source: `ConversationRoot.module.css` `.body` (`--dsh-chat-content-width`,
/// `--dsh-composer-card-max-width`, `--dsh-composer-side-clearance`),
/// `ConversationWidthControls.tsx` (`resolveContentWidth`, default branch),
/// `ChatView.module.css` (`.scroll` side padding, `.column` max width) and
/// `InputBar.module.css` (`.root` side padding, `.card` max width).
///
/// [columnWidth] is the conversation column (the pane left of any right
/// sidebar), `--dsh-conversation-column-width`. dsh's scroll body keeps a 2px
/// margin and reserves the scrollbar gutter (5px on the desktop's thin bar);
/// both the transcript and the composer sit in the box that is left, so the
/// whole axis is centred on it, not on the pane.
final class DshChatAxis {
  const DshChatAxis(this.columnWidth, {this.scrollbar = false});

  /// The axis of the pane [context] is laid out in; [scrollbar] follows the
  /// platform and window rule of the draggable bar (a touch phone has none).
  factory DshChatAxis.of(BuildContext context, double columnWidth) =>
      DshChatAxis(columnWidth, scrollbar: hasScrollbarGutter(context));

  /// Whether the transcript draws a (thin, always visible) scrollbar that
  /// reserves its gutter: wide windows and pointer platforms.
  static bool hasScrollbarGutter(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= dshWideLayoutWidth) return true;
    return switch (ScrollConfiguration.of(context).getPlatform(context)) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      _ => false,
    };
  }

  /// `--dsh-composer-side-clearance` (the input card's side room).
  static const double sideClearance = 16;

  /// `.scrollBody { margin-right: 2px }`.
  static const double scrollBodyMargin = 2;

  /// The scrollbar gutter (`--dsh-scrollbar-width`, 5px thin bar).
  static const double scrollbarGutter = 5;

  final double columnWidth;
  final bool scrollbar;

  /// `--dsh-chat-content-width`: `clamp(680px, 64% of the column, 920px)`.
  double get contentWidth => math.max(680, math.min(columnWidth * 0.64, 920));

  /// What is left of the column for the transcript and the composer.
  double get inner => math.max(
    0,
    columnWidth - scrollBodyMargin - (scrollbar ? scrollbarGutter : 0),
  );

  /// Room on the right of [inner] (margin and gutter) inside the pane.
  double get trailing => columnWidth - inner;

  /// The message column: `.column { max-width }` inside the `.scroll` padding
  /// of clearance + 16 on each side.
  double get messageWidth =>
      math.min(contentWidth, math.max(0, inner - 4 * sideClearance));

  /// The composer card: `--dsh-composer-card-max-width` (content + 32)
  /// between the side clearances.
  double get cardWidth => math.min(
    contentWidth + 2 * sideClearance,
    math.max(0, inner - 2 * sideClearance),
  );

  /// The composer area (card plus its side clearances).
  double get composerWidth => cardWidth + 2 * sideClearance;

  /// Left edge of a centred box of [width] inside the pane.
  double leftOf(double width) => (inner - width) / 2;
}

/// Publishes the axis' [DshChatAxis.contentWidth] to the messages below it
/// (`--dsh-chat-content-width`, which `MessageItem.module.css` reads for the
/// user bubble's cap).
class DshChatContent extends InheritedWidget {
  const DshChatContent({
    super.key,
    required this.contentWidth,
    required super.child,
  });

  final double contentWidth;

  /// The published content width; dsh's own fallback (748, the width the
  /// bubble cap was drawn against) outside a conversation.
  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DshChatContent>()
          ?.contentWidth ??
      748;

  @override
  bool updateShouldNotify(DshChatContent old) =>
      old.contentWidth != contentWidth;
}
