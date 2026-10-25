import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// Reveal a materially clipped title at the Web row's 30px/s, reset instantly
/// on leave, and jump to the tail under reduced motion. Tiny clips keep their
/// ellipsis. The text itself stays selectable through the row hover card.
class WorkspaceTitleMarquee extends StatefulWidget {
  const WorkspaceTitleMarquee({
    super.key,
    required this.text,
    required this.hovered,
    required this.style,
  });
  final String text;
  final bool hovered;
  final TextStyle style;
  @override
  State<WorkspaceTitleMarquee> createState() => _WorkspaceTitleMarqueeState();
}

class _WorkspaceTitleMarqueeState extends State<WorkspaceTitleMarquee> {
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      final range = painter.width - constraints.maxWidth;
      painter.dispose();
      if (!widget.hovered || range <= 8) {
        return DshChromeText(
          widget.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: widget.style,
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.hovered || !scroll.hasClients) return;
        if (MediaQuery.disableAnimationsOf(context)) {
          scroll.jumpTo(scroll.position.maxScrollExtent);
        } else {
          scroll.animateTo(
            scroll.position.maxScrollExtent,
            duration: Duration(milliseconds: (range / .03).ceil()),
            curve: Curves.linear,
          );
        }
      });
      final text = SizedBox(
        height:
            (widget.style.fontSize ?? 14) * (widget.style.height ?? 20 / 14),
        child: SingleChildScrollView(
          key: const ValueKey('workspace-title-marquee'),
          controller: scroll,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: DshChromeText(widget.text, maxLines: 1, style: widget.style),
        ),
      );
      return AnimatedBuilder(
        animation: scroll,
        child: text,
        builder: (context, child) {
          final offset = scroll.hasClients ? scroll.offset : 0.0;
          final end = scroll.hasClients
              ? scroll.position.maxScrollExtent
              : range;
          final ink = context.dsh.labelPrimary;
          return ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              colors: [
                ink.withAlpha(offset > 0 ? 0 : 255),
                ink,
                ink,
                ink.withAlpha(offset < end ? 0 : 255),
              ],
              stops: const [0, .08, .92, 1],
            ).createShader(rect),
            child: child,
          );
        },
      );
    },
  );
}
