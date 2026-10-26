import 'dart:async';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A text controller that draws the composer draft: every atomic chip (a
/// reference chip, the command chip that opens a claimed draft) is the single
/// U+FFFC character of the draft's detect projection, drawn as an inline chip.
/// A placeholder is one character to the text field, so the caret steps over a
/// chip and a deletion removes it whole. Edits flow into [ComposerInput], which
/// reconciles which chips survived; programmatic edits (a pick) flow back.
class ComposerTextController extends TextEditingController {
  ComposerTextController(this.input, {this.onOpenChip}) {
    final s = input.snapshot;
    super.value = TextEditingValue(
      text: s.text,
      selection: TextSelection(baseOffset: s.selStart, extentOffset: s.selEnd),
    );
    _sub = input.state.changes.listen((_) => _fromModel());
    _lexiconSub = input.triggers?.lexiconRevision.changes.listen(
      (_) => notifyListeners(),
    );
    addListener(_toModel);
  }

  final ComposerInput input;

  /// A chip was tapped: open what it names (a file preview).
  final void Function(DraftChip chip)? onOpenChip;

  StreamSubscription<InputSnapshot>? _sub;
  StreamSubscription<int>? _lexiconSub;
  List<InlineSpan> _literalSpans(
    String text,
    int base,
    TextStyle? style,
    BuildContext context,
  ) {
    final lexemes =
        input.triggers
            ?.lexemes(value.text)
            .where((l) => l.start >= base && l.end <= base + text.length)
            .toList() ??
        const <InputLexeme>[];
    if (lexemes.isEmpty) return [TextSpan(text: text)];
    final result = <InlineSpan>[];
    var at = 0;
    for (final lexeme in lexemes) {
      final start = lexeme.start - base, end = lexeme.end - base;
      if (at < start) result.add(TextSpan(text: text.substring(at, start)));
      result.add(
        TextSpan(
          text: text.substring(start, end),
          style: (style ?? const TextStyle()).copyWith(
            color: context.dsh.color('--dsw-alias-state-business-primary'),
          ),
        ),
      );
      at = end;
    }
    if (at < text.length) result.add(TextSpan(text: text.substring(at)));
    return result;
  }

  bool _syncing = false;

  void _toModel() {
    if (_syncing) return;
    final v = value;
    final sel = v.selection;
    final start = sel.isValid ? sel.start : v.text.length;
    final end = sel.isValid ? sel.end : v.text.length;
    final held = input.textChanged(v.text, start, end);
    if (held != v.text) _fromModel();
  }

  void _fromModel() {
    final s = input.snapshot;
    final v = value;
    final sel = v.selection;
    if (v.text == s.text &&
        sel.isValid &&
        sel.start == s.selStart &&
        sel.end == s.selEnd) {
      return;
    }
    _syncing = true;
    try {
      super.value = TextEditingValue(
        text: s.text,
        selection: TextSelection(
          baseOffset: s.selStart.clamp(0, s.text.length),
          extentOffset: s.selEnd.clamp(0, s.text.length),
        ),
      );
    } finally {
      _syncing = false;
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_lexiconSub?.cancel());
    super.dispose();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = value.text;
    final hasLexemes = input.triggers?.lexemes(text).isNotEmpty ?? false;
    if (!text.contains(atomicChar) && !hasLexemes) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final s = input.snapshot;
    final children = <InlineSpan>[];
    var chip = 0;
    var run = 0;
    for (var i = 0; i < text.length; i++) {
      if (text[i] != atomicChar) continue;
      if (i > run) {
        children.addAll(
          _literalSpans(text.substring(run, i), run, style, context),
        );
      }
      run = i + 1;
      if (i == 0 && s.claim != null) {
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: ComposerChip(
              key: const ValueKey('composer-command-chip'),
              label: s.claim!.token.trimRight(),
            ),
          ),
        );
      } else if (chip < s.chips.length) {
        final c = s.chips[chip++];
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: ComposerChip(
              key: ValueKey('composer-chip-${c.source}-$chip'),
              label: c.label,
              appearance: c.appearance,
              invalid: c.invalid,
              onTap: onOpenChip == null ? null : () => onOpenChip!(c),
            ),
          ),
        );
      } else {
        children.add(const TextSpan(text: atomicChar));
      }
    }
    if (run < text.length) {
      children.addAll(_literalSpans(text.substring(run), run, style, context));
    }
    return TextSpan(style: style, children: children);
  }
}

/// Keeps a typed or pasted U+FFFC out of the field (a chip is the only
/// legitimate source of the character); [ComposerInput] strips them as well.
final TextInputFormatter composerPlaceholderFilter =
    FilteringTextInputFormatter.deny(RegExp(atomicChar));

/// One atomic chip of the draft (dsh `ReferenceChip` / `CommandChip` in the
/// composer): the domain glyph, or the trigger marker, and the label, in the
/// business colour.
class ComposerChip extends StatelessWidget {
  const ComposerChip({
    super.key,
    required this.label,
    this.appearance,
    this.invalid = false,
    this.onTap,
  });

  final String label;

  /// `session`, `file` or `folder`; null draws the `@` marker.
  final String? appearance;
  final bool invalid;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final color = invalid
        ? theme.color('--dsw-alias-state-error-primary')
        : theme.color('--dsw-alias-state-business-primary');
    final style = theme.textStyle('--dsw-font-base-16').copyWith(color: color);
    final icon = switch (appearance) {
      'session' => DshIcons.chatLines,
      'file' => DshIcons.browse,
      'folder' => DshIcons.folderClose,
      'skill' => DshIcons.skill,
      _ => null,
    };
    final chip = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              DshIcon(icon, size: 14, color: color),
              const SizedBox(width: 3),
            ] else if (appearance == null && !label.startsWith('/'))
              DshChromeText(
                '@',
                style: style.copyWith(fontWeight: FontWeight.w500),
              ),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(
                  decoration: invalid ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Opacity(
      opacity: invalid ? 0.7 : 1,
      child: onTap == null
          ? chip
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: chip,
            ),
    );
  }
}

/// EditableText requires plain semantics spans. Preview taps use its actual
/// glyph geometry so literal references keep their full text/cursor offsets.
class ComposerLiteralPreview extends StatefulWidget {
  const ComposerLiteralPreview({
    super.key,
    required this.controller,
    required this.child,
  });
  final ComposerTextController controller;
  final Widget child;
  @override
  State<ComposerLiteralPreview> createState() => _ComposerLiteralPreviewState();
}

class _ComposerLiteralPreviewState extends State<ComposerLiteralPreview> {
  PointerDownEvent? down;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) => down = event,
    onPointerCancel: (_) => down = null,
    onPointerUp: (event) {
      final start = down;
      down = null;
      if (start == null ||
          start.pointer != event.pointer ||
          (event.position - start.position).distance > 5 ||
          event.timeStamp - start.timeStamp >
              const Duration(milliseconds: 400)) {
        return;
      }
      RenderEditable? editable;
      void visit(RenderObject child) {
        if (child is RenderEditable) {
          editable = child;
        } else {
          child.visitChildren(visit);
        }
      }

      context.findRenderObject()?.visitChildren(visit);
      final render = editable;
      if (render == null) return;
      final local = render.globalToLocal(event.position);
      final lexemes =
          widget.controller.input.triggers?.lexemes(widget.controller.text) ??
          const <InputLexeme>[];
      for (final lexeme in lexemes) {
        final boxes = render.getBoxesForSelection(
          TextSelection(baseOffset: lexeme.start, extentOffset: lexeme.end),
        );
        if (!boxes.any((box) => box.toRect().contains(local))) continue;
        widget.controller.input.triggers?.openReference(
          lexeme.source,
          lexeme.entry.ref,
          lexeme.entry.appearance,
        );
        break;
      }
    },
    child: widget.child,
  );
}
