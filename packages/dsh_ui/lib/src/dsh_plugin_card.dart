import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'dsh_button.dart';
import 'dsh_corners.dart';
import 'dsh_guide.dart' show DshPluginDefaultArtwork;
import 'dsh_pixel_snap.dart';
import 'dsh_snapped_box.dart';
import 'dsh_single_line_clamp.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';
import 'dsh_recipes.g.dart';

/// Reserves the source card's negative margins in the actual ancestor layout.
/// Unbled content uses [DshPluginCardInset]; card lists retain the full canvas,
/// so Flutter's ancestor hit bounds include the source's extended side target.
class DshPluginCardCanvas extends StatelessWidget {
  const DshPluginCardCanvas({
    super.key,
    required this.constraints,
    required this.children,
  });

  final BoxConstraints constraints;
  final List<Widget> children;

  static EdgeInsets bleedPadding(EdgeInsets padding) => padding.copyWith(
    left: padding.left + DshPluginCardRecipe.horizontalMargin,
    right: padding.right + DshPluginCardRecipe.horizontalMargin,
  );

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: constraints.copyWith(
      maxWidth: constraints.maxWidth - DshPluginCardRecipe.horizontalMargin * 2,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final child in children)
          if (child is DshPluginCardBleed)
            child
          else
            DshPluginCardInset(child: child),
      ],
    ),
  );
}

/// A loaded-card group that uses the canvas margin space for paint and input.
class DshPluginCardBleed extends StatelessWidget {
  const DshPluginCardBleed({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

/// Aligns ordinary page content with the source card's inner content column.
class DshPluginCardInset extends StatelessWidget {
  const DshPluginCardInset({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: -DshPluginCardRecipe.horizontalMargin,
    ),
    child: child,
  );
}

/// The published loaded-card list, within [DshPluginCardCanvas].
class DshPluginCardList extends StatelessWidget {
  const DshPluginCardList({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: DshPluginCardListRecipe.gap),
        children[i],
      ],
    ],
  );
}

/// Source CardHead/PackageCard presentation; host decisions remain at the call.
/// The canonical button owns the card action. Trailing controls are siblings
/// above its stretched target, including while those controls are disabled.
class DshPluginCard extends StatefulWidget {
  const DshPluginCard({
    super.key,
    required this.title,
    required this.semanticLabel,
    required this.onOpen,
    this.description,
    this.image,
    this.tags = const [],
    this.actions = const [],
    this.metadataError,
    this.focusNode,
  });

  final String title, semanticLabel;
  final String? description, metadataError;
  final ImageProvider? image;
  final List<Widget> tags, actions;
  final VoidCallback onOpen;
  final FocusNode? focusNode;

  static const actionKey = ValueKey('dsh-plugin-card-action');
  static const frameKey = ValueKey('dsh-plugin-card-frame');

  @override
  State<DshPluginCard> createState() => _DshPluginCardState();
}

class _DshPluginCardState extends State<DshPluginCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final ground = _hovered
        ? DshSurface.paint(context, theme.color(DshPluginCardRecipe.hoverToken))
        : DshSurface.maybeOf(context);
    final border = dshBorderWidthOf(
      context,
      DshPluginCardRecipe.iconBorderWidth,
    );
    final description = widget.description;
    final titleStyle = theme
        .fixedTextStyle(
          size: DshPluginCardRecipe.titleFontSize,
          line: DshPluginCardRecipe.titleLineHeight,
          weight: DshPluginCardRecipe.titleWeight.round(),
        )
        .copyWith(color: theme.labelPrimary);
    final descriptionStyle = theme
        .fixedTextStyle(
          size: DshPluginCardRecipe.descriptionFontSize,
          line: DshPluginCardRecipe.descriptionLineHeight,
        )
        .copyWith(color: theme.color(DshPluginCardRecipe.descriptionToken));
    final artwork = ExcludeSemantics(
      child: DshContainer(
        key: DshPluginCard.frameKey,
        width: DshPluginCardRecipe.iconWidth + border * 2,
        height: DshPluginCardRecipe.iconHeight + border * 2,
        alignment: Alignment.center,
        decoration: theme.cornerDecoration(
          theme.number(DshPluginCardRecipe.iconRadiusToken),
          borderColor: DshSurface.paint(
            context,
            theme.color(DshPluginCardRecipe.iconBorderToken),
            over: ground != null && ground.a >= 1 ? ground : null,
          ),
          borderWidth: border,
        ),
        child: IconTheme(
          data: IconThemeData(
            color: theme.color(DshPluginCardRecipe.iconLabelToken),
          ),
          child: widget.image == null
              ? const DshPluginDefaultArtwork(
                  size: DshPluginCardRecipe.artworkSize,
                )
              : Image(
                  key: ValueKey(widget.image),
                  image: widget.image!,
                  width: DshPluginCardRecipe.artworkSize,
                  height: DshPluginCardRecipe.artworkSize,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const DshPluginDefaultArtwork(
                    size: DshPluginCardRecipe.artworkSize,
                  ),
                ),
        ),
      ),
    );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(DshPluginCardRecipe.headPadding),
          child: Row(
            children: [
              IgnorePointer(child: artwork),
              const SizedBox(width: DshPluginCardRecipe.headGap),
              Expanded(
                child: IgnorePointer(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: DshPluginCardRecipe.titleRowGap,
                        runSpacing: DshPluginCardRecipe.titleRowGap,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ExcludeSemantics(
                            child: DshChromeText(
                              widget.title,
                              style: titleStyle,
                              maxLines: DshPluginCardRecipe.titleMaxLines
                                  .round(),
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          ...widget.tags,
                        ],
                      ),
                      if (description != null && description.isNotEmpty) ...[
                        const SizedBox(height: DshPluginCardRecipe.mainGap),
                        ExcludeSemantics(
                          child: DshSingleLineClamp(
                            description,
                            style: descriptionStyle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (widget.actions.isNotEmpty) ...[
                const SizedBox(width: DshPluginCardRecipe.headGap),
                Listener(
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < widget.actions.length; i++) ...[
                        if (i > 0)
                          const SizedBox(width: DshPluginCardRecipe.endGap),
                        widget.actions[i],
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (widget.metadataError case final error?)
          IgnorePointer(
            child: Semantics(
              liveRegion: true,
              child: DshChromeText(
                error,
                style: theme
                    .fixedTextStyle(
                      size: DshPluginCardRecipe.errorFontSize,
                      line: DshPluginCardRecipe.errorLineHeight,
                    )
                    .copyWith(
                      color: theme.color(DshPluginCardRecipe.errorToken),
                    ),
              ),
            ),
          ),
      ],
    );
    return _ContourHitTarget(
      shape: theme.cornerBorder(theme.number(DshPluginCardRecipe.radiusToken)),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DshButton(
                key: DshPluginCard.actionKey,
                profile: DshButtonProfile.pluginCard,
                sourceHovered: _hovered,
                focusNode: widget.focusNode,
                semanticLabel: widget.semanticLabel,
                semanticHint: description,
                onPressed: widget.onOpen,
                child: const SizedBox.expand(),
              ),
            ),
            if (ground != null && ground.a >= 1)
              DshSurface(color: ground, child: content)
            else
              content,
          ],
        ),
      ),
    );
  }
}

// Hit clipping only: the source outline paints outside the card contour.
class _ContourHitTarget extends SingleChildRenderObjectWidget {
  const _ContourHitTarget({required this.shape, required super.child});
  final ShapeBorder shape;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderContourHitTarget(shape);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderContourHitTarget renderObject,
  ) {
    renderObject.shape = shape;
  }
}

class _RenderContourHitTarget extends RenderProxyBox {
  _RenderContourHitTarget(this.shape);
  ShapeBorder shape;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      shape.getOuterPath(Offset.zero & size).contains(position) &&
      super.hitTest(result, position: position);
}
