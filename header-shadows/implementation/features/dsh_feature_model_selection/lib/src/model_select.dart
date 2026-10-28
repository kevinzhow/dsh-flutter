import 'dart:async';
import 'dart:math' as math;

import 'package:dsh_client/generated.dart' as session_ns;
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'model_directory.dart';
import 'provider_order.dart';

const String _ns = 'model';

/// The actual two-level ModelSelect menu, anchored above the composer's chip
/// at every viewport size like the published source.
class ModelSeat extends StatefulWidget {
  const ModelSeat({
    super.key,
    required this.directory,
    required this.i18n,
    this.locked = false,
  });
  final ModelDirectory directory;
  final DshI18n i18n;
  final bool locked;
  @override
  State<ModelSeat> createState() => _ModelSeatState();
}

class _ModelSeatState extends State<ModelSeat> {
  final _triggerFocus = FocusNode();
  bool _hover = false, _focusVisible = false;
  String _t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t(_ns, key, params: params);
  @override
  void dispose() {
    _triggerFocus.dispose();
    super.dispose();
  }

  void _toggle(DshPanelController panel) {
    _triggerFocus.requestFocus();
    if (!panel.isOpen) {
      unawaited(
        widget.directory.load().then<void>((_) {}, onError: (Object _) {}),
      );
    }
    panel.toggle();
  }

  @override
  Widget build(BuildContext context) => DshWatch(
    changes: widget.directory.state.changes,
    builder: (context) {
      final theme = context.dsh;
      final state = widget.directory.state.value;
      final view = _View.of(state, _t);
      final waiting =
          view.choice == null && state.status == ModelDirectoryStatus.loading;
      final label = waiting
          ? _t('trigger.loading')
          : (view.choice?.model.name ?? _t('trigger.fallback'));
      final effort = view.effortLabel;
      final aria = waiting
          ? _t('trigger.loading')
          : view.choice == null
          ? _t('trigger.selectAria')
          : effort == null
          ? _t('trigger.aria', {'model': label})
          : _t('trigger.ariaEffort', {'model': label, 'effort': effort});
      final style = theme
          .textStyle(DshModelMenuRecipe.triggerFontToken)
          .copyWith(
            color: theme.color(
              widget.locked
                  ? DshModelMenuRecipe.disabledToken
                  : DshModelMenuRecipe.triggerLabelToken,
            ),
            height:
                DshModelMenuRecipe.triggerLineHeight /
                DshModelMenuRecipe.triggerFontSize,
            fontWeight: FontWeight
                .values[(DshModelMenuRecipe.triggerFontWeight ~/ 100) - 1],
          );
      return DshAnchoredPanel(
        side: DshPanelSide.top,
        align: DshPanelAlign.end,
        menuViewport: true,
        domOffsetGeometry: true,
        gap: DshModelMenuRecipe.anchorGap,
        viewportMargin: DshModelMenuRecipe.portalMargin,
        frameOverlayTop: DshModelMenuRecipe.portalMargin,
        panelBuilder: (context, panel) => ModelSheet(
          directory: widget.directory,
          i18n: widget.i18n,
          onClose: panel.close,
        ),
        builder: (context, panel) => Semantics(
          container: true,
          button: true,
          enabled: !widget.locked,
          label: aria,
          excludeSemantics: true,
          onTap: widget.locked ? null : () => _toggle(panel),
          child: MouseRegion(
            cursor: widget.locked
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: FocusableActionDetector(
              focusNode: _triggerFocus,
              enabled: !widget.locked,
              onShowFocusHighlight: (value) =>
                  setState(() => _focusVisible = value),
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
              },
              actions: {
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    _toggle(panel);
                    return null;
                  },
                ),
              },
              child: GestureDetector(
                key: const ValueKey('model-chip'),
                behavior: HitTestBehavior.opaque,
                onTap: widget.locked ? null : () => _toggle(panel),
                child: DshContainer(
                  constraints: BoxConstraints(
                    maxWidth: math.min(
                      DshModelMenuRecipe.triggerMaxWidth,
                      MediaQuery.sizeOf(context).width *
                          DshModelMenuRecipe.triggerWidthFactor,
                    ),
                  ),
                  height: DshModelMenuRecipe.triggerHeight,
                  padding: const EdgeInsets.only(
                    left: DshModelMenuRecipe.triggerLeftPadding,
                    right: DshModelMenuRecipe.triggerRightPadding,
                  ),
                  decoration: theme.cornerDecoration(
                    theme.number(DshModelMenuRecipe.triggerRadiusToken),
                    color: _hover && !widget.locked
                        ? theme.color(DshModelMenuRecipe.hoverToken)
                        : null,
                    borderColor: _focusVisible && !widget.locked
                        ? theme.focusRingColor
                        : null,
                    borderWidth: _focusVisible && !widget.locked
                        ? theme.focusRingWidth
                        : 0,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: DshChromeText(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: style,
                        ),
                      ),
                      if (effort != null) ...[
                        const SizedBox(width: DshModelMenuRecipe.triggerGap),
                        Flexible(
                          child: DshChromeText(
                            effort,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style.copyWith(
                              color: theme.color(
                                DshModelMenuRecipe.triggerEffortToken,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: DshModelMenuRecipe.triggerGap),
                      if (state.pending != null)
                        const DshStatusDot(DshStatus.running)
                      else
                        Transform.rotate(
                          angle: panel.isOpen ? math.pi : 0,
                          child: DshIcon(
                            DshIcons.chevronDown,
                            size: DshModelMenuRecipe.chevronSize,
                            color: theme.color(
                              DshModelMenuRecipe.triggerEffortToken,
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
      );
    },
  );
}

/// One effort row: [effort] null means the provider default.
class _EffortChoice {
  const _EffortChoice(this.key, this.effort, this.label);
  final String key;
  final String? effort;
  final String label;
}

class _Choice {
  const _Choice(this.group, this.model);
  final session_ns.ModelProviderGroup group;
  final session_ns.ModelCatalogModel model;
}

/// What the seat and the sheet derive from the directory state.
class _View {
  _View(this.state, this.t) {
    groups = orderModelProviders(state.groups, (g) => g.id);
    choices = [
      for (final g in groups)
        for (final m in g.models) _Choice(g, m),
    ];
    final current = state.current;
    if (current != null) {
      for (final c in choices) {
        if (c.group.id == current.provider && c.model.id == current.model) {
          choice = c;
        }
      }
    }
    reasoning = choice?.model.reasoning;
    effective = current?.reasoningEffort ?? reasoning?.defaultEffort;
    if (choice == null) {
      effortLabel = null;
    } else if (reasoning == null) {
      effortLabel = state.retainedEffort;
    } else if (effective == null) {
      effortLabel = t('effort.providerDefault');
    } else {
      effortLabel = effective;
      for (final level in reasoning!.efforts) {
        if (level.id == effective) effortLabel = level.name;
      }
    }
    efforts = reasoning == null
        ? const []
        : [
            if (reasoning!.defaultEffort == null)
              _EffortChoice(
                'provider-default',
                null,
                t('effort.providerDefault'),
              ),
            for (final e in reasoning!.efforts)
              _EffortChoice('effort:${e.id}', e.id, e.name),
          ];
  }

  factory _View.of(
    ModelDirectoryState state,
    String Function(String, [Map<String, Object?>]) t,
  ) => _View(state, t);

  final ModelDirectoryState state;
  final String Function(String, [Map<String, Object?>]) t;
  late final List<session_ns.ModelProviderGroup> groups;
  late final List<_Choice> choices;
  _Choice? choice;
  session_ns.ModelReasoning? reasoning;
  String? effective;
  String? effortLabel;
  late final List<_EffortChoice> efforts;

  bool get showSearch => choices.length > 4;
}

enum _Pane { root, model, effort }

/// Compatibility name for the published bounded ModelSelect menu content.
/// This is a MenuSurface, with no dialog title, dimming mask or sheet route.
class ModelSheet extends StatefulWidget {
  const ModelSheet({
    super.key,
    required this.directory,
    required this.i18n,
    this.onClose,
  });
  final ModelDirectory directory;
  final DshI18n i18n;
  final VoidCallback? onClose;
  @override
  State<ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<ModelSheet> {
  _Pane _pane = _Pane.root;
  bool _paneChosen = false, _lastWasLoad = true;
  String _query = '';
  String? _toast;
  String? _lastRevealed;
  int? _highlight;
  Timer? _toastTimer;
  final _searchFocus = FocusNode();
  final _rowFocus = <String, FocusNode>{};
  FocusNode? _programmaticFocus;
  final _searchController = TextEditingController();
  FocusNode _node(String id) => _rowFocus.putIfAbsent(id, () {
    final node = FocusNode();
    node.addListener(() {
      if (node.hasFocus) _reveal(id);
    });
    return node;
  });
  void _reveal(String id) {
    final rowContext = _rowFocus[id]?.context;
    final object = rowContext?.findRenderObject();
    if (rowContext == null || object == null) return;
    final position = Scrollable.maybeOf(rowContext)?.position;
    position?.ensureVisible(
      object,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
    position?.ensureVisible(
      object,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  String _t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t(_ns, key, params: params);
  void _close() =>
      widget.onClose != null ? widget.onClose!() : Navigator.of(context).pop();
  @override
  void dispose() {
    _toastTimer?.cancel();
    _searchFocus.dispose();
    _searchController.dispose();
    for (final node in _rowFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _reload() {
    _lastWasLoad = true;
    setState(() {});
    unawaited(
      widget.directory.load().then<void>((_) {}, onError: (Object _) {}),
    );
  }

  Future<void> _submit(session_ns.ModelSelection selection) async {
    _lastWasLoad = false;
    final outcome = await widget.directory.select(selection);
    if (!mounted) return;
    if (outcome.ok) {
      _close();
      return;
    }
    final error = outcome.error!;
    setState(() {
      _toast = error.code == 'session/writer-held'
          ? _t('error.sessionInUse')
          : _t('error.action', {'message': '${error.code}: ${error.message}'});
    });
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _chooseModel(_View view, _Choice choice) {
    final current = view.state.current;
    if (current?.provider == choice.group.id &&
        current?.model == choice.model.id) {
      _close();
      return;
    }
    unawaited(
      _submit(
        session_ns.ModelSelection(
          provider: choice.group.id,
          model: choice.model.id,
          reasoningEffort: choice.model.reasoning?.defaultEffort,
        ),
      ),
    );
  }

  void _chooseEffort(_View view, _EffortChoice level) {
    final current = view.state.current;
    if (current == null) return;
    if (view.effective == level.effort) {
      _close();
      return;
    }
    unawaited(
      _submit(
        session_ns.ModelSelection(
          provider: current.provider,
          model: current.model,
          reasoningEffort: level.effort,
        ),
      ),
    );
  }

  _Pane _shown(_View view) =>
      !_paneChosen && view.choice == null ? _Pane.model : _pane;
  List<_Choice> _visible(_View view) => [
    for (final group in view.groups)
      for (final model in rankByName(
        group.models,
        view.showSearch ? _query.trim() : '',
        name: (m) => m.name,
      ))
        _Choice(group, model),
  ];
  int _active(_View view, List<_Choice> choices) {
    final index = choices.indexWhere(
      (c) =>
          c.group.id == view.state.current?.provider &&
          c.model.id == view.state.current?.model,
    );
    return (_highlight ?? math.max(0, index)).clamp(
      0,
      math.max(0, choices.length - 1),
    );
  }

  void _drill(_Pane pane, _View view) {
    setState(() {
      _pane = pane;
      _paneChosen = true;
      _query = '';
      _highlight = null;
      _lastRevealed = null;
      _programmaticFocus = null;
      _searchController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (pane == _Pane.model && view.showSearch) {
        _searchFocus.requestFocus();
        return;
      }
      final id = pane == _Pane.effort
          ? 'effort-option-${view.efforts.where((e) => e.effort == view.effective).firstOrNull?.key ?? view.efforts.firstOrNull?.key}'
          : 'model-option-${view.choice?.group.id}/${view.choice?.model.id}';
      final node = _rowFocus[id] ?? _rowFocus.values.firstOrNull;
      if (node == null) return;
      // Source pane entry unmounts the clicked root button before focusing
      // the checked option. Chromium gives that programmatic focus a visible
      // cue even after pointer entry; keep the intent local to this focus.
      setState(() => _programmaticFocus = node);
      node.requestFocus();
    });
  }

  void _back(_View view) {
    final from = _shown(view);
    if (from == _Pane.root || view.choice == null) {
      _close();
      return;
    }
    setState(() {
      _pane = _Pane.root;
      _paneChosen = true;
      _query = '';
      _highlight = null;
      _programmaticFocus = null;
      _searchController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _node(from == _Pane.effort ? 'model-root-effort' : 'model-root-model')
            .requestFocus();
      }
    });
  }

  KeyEventResult _key(KeyEvent event, _View view) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape ||
        (key == LogicalKeyboardKey.tab &&
            HardwareKeyboard.instance.isShiftPressed)) {
      _back(view);
      return KeyEventResult.handled;
    }
    final pane = _shown(view),
        models = _visible(view),
        busy = view.state.pending != null;
    if (pane == _Pane.model && view.showSearch) {
      if (key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.arrowUp) {
        if (!busy && models.isNotEmpty) {
          setState(
            () => _highlight =
                (_active(view, models) +
                    (key == LogicalKeyboardKey.arrowDown
                        ? 1
                        : models.length - 1)) %
                models.length,
          );
        }
        _searchFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if ((key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.tab) &&
          _searchFocus.hasFocus) {
        if (!busy && models.isNotEmpty) {
          _chooseModel(view, models[_active(view, models)]);
        }
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.tab) {
      final ids = switch (pane) {
        _Pane.root => [
          'model-root-model',
          if (view.reasoning != null) 'model-root-effort',
        ],
        _Pane.model => [
          for (final c in models) 'model-option-${c.group.id}/${c.model.id}',
        ],
        _Pane.effort => [
          for (final e in view.efforts) 'effort-option-${e.key}',
        ],
      };
      if (!busy && ids.isNotEmpty) {
        final index = ids.indexWhere((id) => _node(id).hasFocus);
        final next = key == LogicalKeyboardKey.arrowUp
            ? (index < 0
                  ? ids.length - 1
                  : (index + ids.length - 1) % ids.length)
            : (index + 1) % ids.length;
        _node(ids[next]).requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => DshWatch(
    changes: widget.directory.state.changes,
    builder: (context) {
      final theme = context.dsh,
          view = _View.of(widget.directory.state.value, _t);
      final size = MediaQuery.sizeOf(context);
      // ModelSelect's published .menu retains CSS content-box sizing. Its
      // min/max width and max-height bound the content; MenuSurface padding
      // sits outside those bounds. CSS vw/vh remain fractional here, while
      // domOffsetGeometry handles JS's integer offset/viewport placement.
      final surfaceInset = DshModelMenuRecipe.padding * 2;
      final maxContentWidth = math.min(
        DshModelMenuRecipe.maxWidth,
        math.max(0.0, size.width - DshModelMenuRecipe.viewportWidthInset),
      );
      final minContentWidth = math.min(
        DshModelMenuRecipe.minWidth,
        maxContentWidth,
      );
      final width =
          _contentWidth(theme, view).clamp(minContentWidth, maxContentWidth) +
          surfaceInset;
      return Focus(
        autofocus: true,
        onKeyEvent: (_, event) => _key(event, view),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: minContentWidth + surfaceInset,
            maxWidth: maxContentWidth + surfaceInset,
            maxHeight:
                math.max(
                  0.0,
                  math.min(
                    DshModelMenuRecipe.maxHeight,
                    size.height - DshModelMenuRecipe.viewportHeightInset,
                  ),
                ) +
                surfaceInset,
          ),
          child: SizedBox(
            width: width.toDouble(),
            child: DshMenuSurface(
              key: const ValueKey('model-sheet'),
              padding: const EdgeInsets.all(DshModelMenuRecipe.padding),
              child: Semantics(
                label: _t('menu.aria'),
                container: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: switch (_shown(view)) {
                        _Pane.root => _root(view),
                        _Pane.model => _models(theme, view),
                        _Pane.effort => _efforts(theme, view),
                      },
                    ),
                    if (_toast != null) _banner(theme, _toast!, null),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  double _contentWidth(DshThemeData theme, _View view) {
    double measure(String text, String token) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: theme.textStyle(token)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final pane = _shown(view);
    final inner = pane == _Pane.root
        ? [
                measure(_t('menu.model'), DshModelMenuRecipe.cellFontToken) +
                    measure(
                      view.choice?.model.name ?? _t('trigger.fallback'),
                      DshModelMenuRecipe.cellFontToken,
                    ),
                if (view.reasoning != null)
                  measure(_t('menu.effort'), DshModelMenuRecipe.cellFontToken) +
                      measure(
                        view.effortLabel ?? '',
                        DshModelMenuRecipe.cellFontToken,
                      ),
              ].fold(0.0, math.max) +
              DshModelMenuRecipe.cellHorizontalPadding * 2 +
              DshModelMenuRecipe.cellGap * 2 +
              DshModelMenuRecipe.chevronSize
        : (pane == _Pane.model
                      ? _visible(view).map((c) => c.model.name)
                      : view.efforts.map((e) => e.label))
                  .map(
                    (label) => measure(label, DshModelMenuRecipe.rowFontToken),
                  )
                  .fold(0.0, math.max) +
              DshModelMenuRecipe.rowHorizontalPadding * 2 +
              DshModelMenuRecipe.rowGap +
              DshModelMenuRecipe.checkSize;
    return inner;
  }

  Widget _root(_View view) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _cell(
        'model-root-model',
        _t('menu.model'),
        view.choice?.model.name ?? _t('trigger.fallback'),
        () => _drill(_Pane.model, view),
      ),
      if (view.reasoning != null)
        _cell(
          'model-root-effort',
          _t('menu.effort'),
          view.effortLabel ?? '',
          () => _drill(_Pane.effort, view),
        ),
    ],
  );
  Widget _cell(String id, String label, String value, VoidCallback action) =>
      DshMenuItemButton(
        key: ValueKey(id),
        profile: DshMenuItemProfile.modelCell,
        label: label,
        value: value,
        focusNode: _node(id),
        onPressed: action,
        onDismiss: () => _back(_View.of(widget.directory.state.value, _t)),
      );
  Widget _banner(
    DshThemeData theme,
    String text,
    VoidCallback? retry, {
    bool warning = false,
  }) => DshContainer(
    key: const ValueKey('model-banner'),
    margin: const EdgeInsets.only(bottom: DshModelMenuRecipe.errorBottomMargin),
    padding: const EdgeInsets.symmetric(
      horizontal: DshModelMenuRecipe.errorHorizontalPadding,
      vertical: DshModelMenuRecipe.errorVerticalPadding,
    ),
    decoration: theme.cornerDecoration(
      theme.number(DshModelMenuRecipe.radiusToken),
      color: theme.color(
        warning
            ? DshModelMenuRecipe.warningFillToken
            : DshModelMenuRecipe.errorFillToken,
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DshChromeText(
            text,
            style: theme
                .textStyle(DshModelMenuRecipe.errorFontToken)
                .copyWith(
                  color: theme.color(
                    warning
                        ? DshModelMenuRecipe.warningLabelToken
                        : DshModelMenuRecipe.errorLabelToken,
                  ),
                  height:
                      DshModelMenuRecipe.errorLineHeight /
                      DshModelMenuRecipe.errorFontSize,
                ),
          ),
        ),
        if (retry != null) ...[
          const SizedBox(width: DshModelMenuRecipe.errorGap),
          GestureDetector(
            key: const ValueKey('model-retry'),
            onTap: retry,
            child: DshChromeText(
              _t('retry'),
              style: theme
                  .textStyle(DshModelMenuRecipe.errorFontToken)
                  .copyWith(
                    fontWeight:
                        FontWeight.values[(DshModelMenuRecipe.retryFontWeight ~/
                                100) -
                            1],
                    color: theme.color(
                      warning
                          ? DshModelMenuRecipe.warningLabelToken
                          : DshModelMenuRecipe.errorLabelToken,
                    ),
                    height:
                        DshModelMenuRecipe.errorLineHeight /
                        DshModelMenuRecipe.errorFontSize,
                  ),
            ),
          ),
        ],
      ],
    ),
  );
  Widget _note(DshThemeData theme, String text) => Padding(
    padding: const EdgeInsets.all(DshModelMenuRecipe.statusPadding),
    child: DshChromeText(
      text,
      style: theme
          .textStyle(DshModelMenuRecipe.statusFontToken)
          .copyWith(
            color: theme.color(DshModelMenuRecipe.statusToken),
            height:
                DshModelMenuRecipe.statusLineHeight /
                DshModelMenuRecipe.statusFontSize,
          ),
    ),
  );
  Widget _row(
    _View view, {
    required String id,
    required String label,
    required bool selected,
    required bool pending,
    required VoidCallback onTap,
    bool active = false,
    VoidCallback? onHover,
  }) => DshMenuItemButton(
    key: ValueKey(id),
    profile: DshMenuItemProfile.modelOption,
    label: label,
    selected: selected,
    active: active,
    disabled: view.state.pending != null,
    focusNode: _node(id),
    focusVisible: _programmaticFocus == _node(id) ? true : null,
    onPressed: onTap,
    onHover: onHover,
    onDismiss: () => _back(view),
    pending: pending,
    onFocusChange: (focused) {
      if (focused) onHover?.call();
      if (mounted && !focused && _programmaticFocus == _node(id)) {
        setState(() => _programmaticFocus = null);
      }
    },
  );
  Widget _models(DshThemeData theme, _View view) {
    final state = view.state;
    final query = view.showSearch ? _query.trim() : '';
    final groups = [
      for (final group in view.groups)
        (
          group: group,
          models: rankByName(group.models, query, name: (m) => m.name),
        ),
    ].where((g) => g.models.isNotEmpty).toList();
    final visible = _visible(view), activeIndex = _active(view, _visible(view));
    if (visible.isNotEmpty) {
      final active = visible[activeIndex];
      final id = 'model-option-${active.group.id}/${active.model.id}';
      if (_lastRevealed != id) {
        _lastRevealed = id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _reveal(id);
        });
      }
    }
    var index = 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (view.showSearch)
          Padding(
            padding: const EdgeInsets.only(
              top: DshModelMenuRecipe.searchTopMargin,
              bottom: DshModelMenuRecipe.searchBottomMargin,
            ),
            child: Stack(
              alignment: Alignment.centerRight,
              children: [
                DshInput(
                  key: const ValueKey('model-search'),
                  profile: DshInputProfile.modelSearch,
                  reserveSearchClear: _query.isNotEmpty,
                  controller: _searchController,
                  focusNode: _searchFocus,
                  placeholder: _t('search.placeholder'),
                  semanticLabel: _t('search.placeholder'),
                  enabled: state.pending == null,
                  onChanged: (q) => setState(() {
                    _query = q;
                    _highlight = 0;
                  }),
                ),
                if (_query.isNotEmpty)
                  Positioned(
                    right: DshModelMenuRecipe.searchClearRight,
                    child: GestureDetector(
                      key: const ValueKey('model-search-clear'),
                      behavior: HitTestBehavior.opaque,
                      onTap: state.pending != null
                          ? null
                          : () {
                              setState(() {
                                _query = '';
                                _highlight = 0;
                                _searchController.clear();
                              });
                              _searchFocus.requestFocus();
                            },
                      child: Semantics(
                        button: true,
                        label: _t('search.clear'),
                        child: SizedBox.square(
                          dimension: DshModelMenuRecipe.searchClearSize,
                          child: Center(
                            child: DshIcon(
                              DshIcons.closeFill,
                              size: DshModelMenuRecipe.chevronSize,
                              color: theme.labelSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (state.status == ModelDirectoryStatus.loading)
          _note(theme, _t('status.loading')),
        if (state.error != null && _lastWasLoad)
          _banner(theme, _t('error.action', {'message': state.error}), _reload),
        for (final failure in state.failures)
          _banner(
            theme,
            _t('warning.groupLoad', {
              'name': failure.id == 'deepseek-account'
                  ? _t('provider.account')
                  : failure.name,
              'message': failure.message,
            }),
            _reload,
            warning: true,
          ),
        Flexible(
          child: CustomScrollView(
            key: const ValueKey('model-list'),
            shrinkWrap: true,
            slivers: [
              for (var groupIndex = 0; groupIndex < groups.length; groupIndex++)
                DshMenuGroup(
                  label: groups[groupIndex].group.id == 'deepseek-account'
                      ? _t('provider.account')
                      : groups[groupIndex].group.name,
                  headingKey: ValueKey(
                    'model-group-${groups[groupIndex].group.id}',
                  ),
                  separated: groupIndex > 0,
                  children: [
                    for (final model in groups[groupIndex].models)
                      _row(
                        view,
                        id: 'model-option-${groups[groupIndex].group.id}/${model.id}',
                        label: model.name,
                        selected:
                            state.current?.provider ==
                                groups[groupIndex].group.id &&
                            state.current?.model == model.id,
                        pending:
                            state.pending?.provider ==
                                groups[groupIndex].group.id &&
                            state.pending?.model == model.id,
                        active: index++ == activeIndex && visible.isNotEmpty,
                        onHover: () {
                          final at = visible.indexWhere(
                            (c) =>
                                c.group.id == groups[groupIndex].group.id &&
                                c.model.id == model.id,
                          );
                          setState(() => _highlight = at);
                        },
                        onTap: () => _chooseModel(
                          view,
                          _Choice(groups[groupIndex].group, model),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        if (state.status == ModelDirectoryStatus.ready && groups.isEmpty)
          _note(
            theme,
            _t(view.choices.isEmpty ? 'empty.models' : 'search.empty'),
          ),
      ],
    );
  }

  Widget _efforts(DshThemeData theme, _View view) {
    if (view.efforts.isEmpty) return _note(theme, _t('empty.efforts'));
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (view.state.error != null && _lastWasLoad)
            _banner(
              theme,
              _t('error.action', {'message': view.state.error}),
              _reload,
            ),
          for (final level in view.efforts)
            _row(
              view,
              id: 'effort-option-${level.key}',
              label: level.label,
              selected: view.effective == level.effort,
              pending:
                  view.state.pending != null &&
                  view.state.pending?.reasoningEffort == level.effort,
              onTap: () => _chooseEffort(view, level),
            ),
        ],
      ),
    );
  }
}
