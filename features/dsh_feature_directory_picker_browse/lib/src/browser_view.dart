import 'dart:async';

import 'package:dsh_client/generated_directory_picker.dart'
    show DirectoryEntry, DirectoryListing;
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/dsh_theme.dart' show DshThemeData;
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart'
    show TextField, InputDecoration, InputBorder;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'browser_model.dart';
import 'flex_wrap.dart';

const String _ns = 'directory-browser';

/// The in-app directory browser (dsh `DirectoryBrowser`): title, a breadcrumb
/// bar that turns into a path editor, the Miller columns, and the footer with
/// New folder, the hidden-files toggle, Cancel and Open.
///
/// The layout is dsh's at every width: two columns of at least 256px, side by
/// side, scrolling sideways when the card is narrower, the child pane pinned
/// into view; the footer wraps item by item.
class DirectoryBrowserView extends StatefulWidget {
  const DirectoryBrowserView({
    super.key,
    required this.model,
    required this.i18n,
    required this.busy,
    required this.onOpen,
    required this.onClose,
  });

  final DirectoryBrowserModel model;
  final DshI18n i18n;

  /// The owner is adopting a picked path: every control is inert.
  final bool busy;
  final void Function(String path) onOpen;
  final void Function() onClose;

  @override
  State<DirectoryBrowserView> createState() => _DirectoryBrowserViewState();
}

class _DirectoryBrowserViewState extends State<DirectoryBrowserView> {
  final TextEditingController _path = TextEditingController();
  final FocusNode _pathFocus = FocusNode(debugLabel: 'directory-path-input');
  final FocusNode _editZone = FocusNode(debugLabel: 'directory-edit-zone');
  final ScrollController _trail = ScrollController();
  final ScrollController _millerScroll = ScrollController();
  final ValueNotifier<bool> _zoneLit = ValueNotifier(false);
  StreamSubscription<BrowserState>? _sub;
  String? _lastTail;
  bool _createShown = false;
  bool _refocusZone = false;

  DirectoryBrowserModel get _m => widget.model;
  BrowserState get _s => _m.value;

  @override
  void initState() {
    super.initState();
    _sub = _m.state.changes.listen(_onState);
    _syncDraft();
    // A browser that opens with a child pane shows it (dsh pins on mount too).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _millerScroll.hasClients && _s.child != null) {
        _millerScroll.jumpTo(_millerScroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _path.dispose();
    _pathFocus.dispose();
    _editZone.dispose();
    _trail.dispose();
    _millerScroll.dispose();
    _zoneLit.dispose();
    super.dispose();
  }

  void _syncDraft() {
    final draft = _s.pathDraft;
    if (draft != null && _path.text != draft) {
      _path.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
    }
  }

  void _onState(BrowserState s) {
    if (!mounted) return;
    final hadDraft = _path.text.isNotEmpty || _pathFocus.hasFocus;
    _syncDraft();
    if (s.pathDraft == null && hadDraft && _refocusZone) {
      _refocusZone = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && FocusManager.instance.primaryFocus == null) {
          _editZone.requestFocus();
        }
      });
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
    if (s.folderDraft != null && !_createShown) {
      _createShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showCreate());
    }
    // Pin the tail of a deep chain into view, and the child pane on a phone.
    final tail = (s.child ?? s.parent)?.path;
    if (tail != _lastTail) {
      _lastTail = tail;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_trail.hasClients) {
          _trail.jumpTo(_trail.position.maxScrollExtent);
        }
        // On a narrow card descent would hide behind the edge: pin the child
        // pane into view the way the crumb tail pins.
        if (_millerScroll.hasClients && _s.child != null) {
          _millerScroll.jumpTo(_millerScroll.position.maxScrollExtent);
        }
      });
    }
  }

  String _t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t(_ns, key, params: params);

  bool get _inert => widget.busy || _s.folderDraft != null;

  Future<void> _showCreate() async {
    if (!mounted) return;
    await showDshDialog<void>(
      context,
      label: _t('browser.newFolder'),
      builder: (ctx) => CreateFolderForm(model: _m, i18n: widget.i18n),
    );
    _createShown = false;
    // A dismissal (scrim, Escape, drag, Back) cancels the draft.
    if (mounted && _m.value.folderDraft != null) _m.cancelCreate();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final s = _s;
    final crumbSource = s.crumbSource;
    final crumbs = crumbSource == null
        ? const <DirectoryEntry>[]
        : displayCrumbs(crumbSource, _t('browser.home'));
    final typedPrefix = _m.typedPrefix;
    final truncated =
        (s.parent?.truncated ?? false) || (s.child?.truncated ?? false);
    return PopScope(
      canPop: !widget.busy,
      child: FocusScope(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent ||
              event.logicalKey != LogicalKeyboardKey.escape) {
            return KeyEventResult.ignored;
          }
          if (s.pathDraft != null) {
            _refocusZone = _pathFocus.hasFocus;
            _m.cancelPathEdit();
            return KeyEventResult.handled;
          }
          // Escape closes the dialog, unless the nested create dialog or an
          // adoption in flight owns the interaction.
          if (_inert) return KeyEventResult.ignored;
          widget.onClose();
          return KeyEventResult.handled;
        },
        onFocusChange: (has) {
          // Focus leaving the card cancels an open editor (dsh's blur guard);
          // a focus move that stays inside it keeps the draft.
          if (!has && _s.pathDraft != null && mounted) {
            _refocusZone = false;
            _m.cancelPathEdit();
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(theme, crumbs),
            Expanded(child: _content(theme, typedPrefix, truncated)),
            _footer(theme),
          ],
        ),
      ),
    );
  }

  // ---- header ------------------------------------------------------------

  Widget _header(DshThemeData theme, List<DirectoryEntry> crumbs) {
    final s = _s;
    final editing = s.pathDraft != null;
    final title = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 28),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Semantics(
          header: true,
          child: DshChromeText(
            _t('browser.title'),
            key: const ValueKey('directory-title'),
            style: theme
                .textStyle('--dsw-font-base-strong-16')
                .copyWith(color: theme.labelPrimary, height: 24 / 16),
          ),
        ),
      ),
    );
    return DshDecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.color('--dsw-alias-border-l3'),
            width: dshHairlineOf(context),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: const EdgeInsets.only(left: 24), child: title),
            const SizedBox(height: 8),
            // dsh's `margin-left: -9px` pays back the border and padding so
            // the crumb text keeps the title's column.
            Padding(
              padding: const EdgeInsets.only(left: 15),
              child: _crumbBar(theme, crumbs, editing),
            ),
          ],
        ),
      ),
    );
  }

  Widget _crumbBar(
    DshThemeData theme,
    List<DirectoryEntry> crumbs,
    bool editing,
  ) {
    // The bar IS the editor's box: it carries the outline and the padding, and
    // lights when the edit zone is hovered or focused (never for a crumb).
    return ValueListenableBuilder<bool>(
      valueListenable: _zoneLit,
      builder: (context, zoneLit, _) {
        final lit = editing || zoneLit;
        return DshDecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: lit
                  ? theme.color('--dsw-alias-border-l2')
                  : const Color(0x00000000),
              width: dshBorderWidthOf(context, 1),
            ),
            borderRadius: BorderRadius.circular(theme.radiusSm),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 24),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: editing
                  ? _pathInput(theme)
                  : SizedBox(
                      height: 24,
                      // The empty remainder of the bar is the path-edit
                      // affordance, the crumbs sit above it: the trail is as
                      // wide as its crumbs (then it scrolls) and the zone
                      // takes the rest, glyph at its right edge.
                      child: Stack(
                        children: [
                          Positioned.fill(child: _editZoneButton(theme)),
                          Padding(
                            padding: const EdgeInsets.only(right: 38),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: ListView(
                                key: const ValueKey('directory-crumbs'),
                                controller: _trail,
                                scrollDirection: Axis.horizontal,
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                children: [
                                  for (var i = 0; i < crumbs.length; i++)
                                    _crumb(
                                      theme,
                                      crumbs[i],
                                      i,
                                      i == crumbs.length - 1,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _crumb(
    DshThemeData theme,
    DirectoryEntry crumb,
    int index,
    bool last,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (index > 0) ...[
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: DshIcon(
              DshIcons.chevronRight,
              size: 12,
              color: theme.color('--dsw-alias-label-tertiary'),
            ),
          ),
        ],
        _Crumb(
          key: ValueKey('crumb-${crumb.path}'),
          label: crumb.name,
          enabled: !_inert,
          onPressed: () => _m.navigate(crumb.path),
        ),
        if (!last) const SizedBox(width: 4),
      ],
    );
  }

  Widget _editZoneButton(DshThemeData theme) {
    final disabled = _inert;
    return _EditZone(
      focusNode: _editZone,
      label: _t('browser.editPath'),
      disabled: disabled,
      glyph: DshIcon(
        DshIcons.edit,
        size: 14,
        color: disabled
            ? theme.color('--dsw-alias-label-caption')
            : theme.color('--dsw-alias-label-tertiary'),
      ),
      hoverGlyph: DshIcon(
        DshIcons.edit,
        size: 14,
        color: theme.color('--dsw-alias-label-primary'),
      ),
      onLit: (v) => _zoneLit.value = v,
      onPressed: () {
        _zoneLit.value = false;
        _m.startPathEdit();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _pathFocus.requestFocus();
        });
      },
    );
  }

  Widget _pathInput(DshThemeData theme) {
    final style = theme
        .textStyle('--dsw-font-xs-13')
        .copyWith(color: theme.labelPrimary, height: 20 / 13);
    return SizedBox(
      height: 22,
      child: Semantics(
        textField: true,
        label: _t('browser.editPath'),
        child: TextField(
          key: const ValueKey('directory-path-input'),
          controller: _path,
          focusNode: _pathFocus,
          enabled: !_inert,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          maxLines: 1,
          style: style,
          cursorColor: theme.labelPrimary,
          textInputAction: TextInputAction.go,
          decoration: const InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 1),
          ),
          onChanged: _m.setPathDraft,
          onSubmitted: (_) {
            if (_path.text.trim().isEmpty) return;
            _refocusZone = true;
            _m.submitPath();
          },
        ),
      ),
    );
  }

  // ---- content -----------------------------------------------------------

  /// The Miller row (dsh `.millerRow`): columns of at least 256px sharing the
  /// width (a solo column takes it all), 12px either side of a hairline divider;
  /// when they do not fit the row scrolls sideways and the child pane is pinned
  /// into view.
  Widget _miller(DshThemeData theme, String? typedPrefix) {
    final s = _s;
    final parent = s.parent;
    final child = s.child;
    final hair = dshHairlineOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = [
          if (parent != null) 0,
          if (s.twoPane && child != null) 1,
        ];
        final items = columns.length + (s.twoPane ? 1 : 0);
        final gaps = items > 1 ? 12.0 * (items - 1) : 0.0;
        final divider = s.twoPane ? hair : 0.0;
        final share = columns.isEmpty
            ? 0.0
            : (constraints.maxWidth - gaps - divider) / columns.length;
        final width = share < 256 ? 256.0 : share;
        Widget column(int which) {
          final listing = which == 0 ? parent! : child!;
          return SizedBox(
            width: width,
            child: _Level(
              key: ValueKey('level-${listing.path}'),
              listing: listing,
              selectedPath: which == 0 ? s.selected?.path : null,
              busy: _inert,
              onPick: which == 0 ? _m.select : _m.advance,
              showHidden: s.showHidden,
              filterPrefix: which == 0 && child != null ? null : typedPrefix,
              pathEditing: s.draftPending,
            ),
          );
        }

        final children = <Widget>[
          if (parent != null) column(0),
          if (s.twoPane)
            SizedBox(
              width: hair,
              child: ColoredBox(color: theme.color('--dsw-alias-border-l3')),
            ),
          if (s.twoPane && child != null) column(1),
        ];
        final spaced = <Widget>[
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            children[i],
          ],
        ];
        return SingleChildScrollView(
          key: const ValueKey('directory-miller'),
          controller: _millerScroll,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            height: constraints.maxHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: spaced,
            ),
          ),
        );
      },
    );
  }

  Widget _content(DshThemeData theme, String? typedPrefix, bool truncated) {
    final s = _s;
    final status = theme
        .textStyle('--dsw-font-xxs-12')
        .copyWith(height: 18 / 12);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _miller(theme, typedPrefix)),
              if (truncated)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 120, 4),
                  child: Semantics(
                    liveRegion: true,
                    child: DshChromeText(
                      _t('browser.truncated'),
                      key: const ValueKey('directory-truncated'),
                      style: status.copyWith(color: theme.labelSecondary),
                    ),
                  ),
                ),
              if (s.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 120, 4),
                  child: Semantics(
                    liveRegion: true,
                    child: DshChromeText(
                      s.error!,
                      key: const ValueKey('directory-error'),
                      style: status.copyWith(
                        color: theme.color('--dsw-alias-state-error-primary'),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (s.loading && s.slowScan)
            Positioned(
              right: 0,
              bottom: -8,
              child: DshDecoratedBox(
                decoration: BoxDecoration(
                  color: theme.color('--dsw-alias-bg-layer-2'),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: Semantics(
                    liveRegion: true,
                    child: DshChromeText(
                      _t('browser.loading'),
                      key: const ValueKey('directory-loading'),
                      style: status.copyWith(color: theme.labelSecondary),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---- footer ------------------------------------------------------------

  Widget _footer(DshThemeData theme) {
    final s = _s;
    final inert = _inert;
    final newFolder = DshButton(
      key: const ValueKey('directory-new-folder'),
      variant: DshButtonVariant.outline,
      icon: DshIcon(DshIcons.plus, size: 14, color: theme.labelPrimary),
      onPressed: _m.canCreate && !inert ? _m.startCreate : null,
      child: Text(_t('browser.newFolder')),
    );
    final hidden = _HiddenToggle(
      label: _t('browser.showHidden'),
      on: s.showHidden,
      enabled: !inert,
      onPressed: _m.toggleHidden,
    );
    final cancel = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 72),
      child: DshButton(
        key: const ValueKey('directory-cancel'),
        variant: DshButtonVariant.outline,
        onPressed: inert ? null : widget.onClose,
        child: Center(widthFactor: 1, child: Text(_t('browser.cancel'))),
      ),
    );
    final target = _m.openTarget;
    final open = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 72),
      child: DshButton(
        key: const ValueKey('directory-open'),
        variant: DshButtonVariant.primary,
        onPressed: _m.canOpen && !inert && target != null
            ? () => widget.onOpen(target)
            : null,
        child: Center(widthFactor: 1, child: Text(_t('browser.open'))),
      ),
    );
    return DshDecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.color('--dsw-alias-border-l3'),
            width: dshHairlineOf(context),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        // dsh's `flex-wrap: wrap` row: items wrap one by one when the card is
        // narrow, the gap pushes Cancel and Open to the far edge otherwise.
        child: FlexWrapRow(
          spacerIndex: 2,
          children: [newFolder, hidden, const SizedBox.shrink(), cancel, open],
        ),
      ),
    );
  }
}

/// The empty remainder of the crumb bar: a click target that opens the path
/// editor, with the pencil glyph seated at its right edge.
class _EditZone extends StatefulWidget {
  const _EditZone({
    required this.focusNode,
    required this.label,
    required this.disabled,
    required this.glyph,
    required this.hoverGlyph,
    required this.onPressed,
    required this.onLit,
  });

  final FocusNode focusNode;
  final String label;
  final bool disabled;
  final Widget glyph;
  final Widget hoverGlyph;
  final VoidCallback onPressed;

  /// Reports whether hover or keyboard focus lights the crumb bar.
  final void Function(bool lit) onLit;

  @override
  State<_EditZone> createState() => _EditZoneState();
}

class _EditZoneState extends State<_EditZone> {
  bool _hover = false;
  bool _focused = false;

  void _setHover(bool v) {
    if (_hover == v) return;
    setState(() => _hover = v);
    widget.onLit(v && !widget.disabled);
  }

  @override
  Widget build(BuildContext context) {
    final lit = (_hover || _focused) && !widget.disabled;
    return Semantics(
      button: true,
      enabled: !widget.disabled,
      label: widget.label,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        enabled: !widget.disabled,
        mouseCursor: widget.disabled
            ? SystemMouseCursors.basic
            : SystemMouseCursors.text,
        onShowFocusHighlight: (v) {
          setState(() => _focused = v);
          widget.onLit((v || _hover) && !widget.disabled);
        },
        onShowHoverHighlight: _setHover,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: GestureDetector(
          key: const ValueKey('directory-edit-zone'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.disabled ? null : widget.onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 34, minHeight: 22),
            child: Align(
              alignment: Alignment.centerRight,
              child: lit ? widget.hoverGlyph : widget.glyph,
            ),
          ),
        ),
      ),
    );
  }
}

/// One breadcrumb: a text button that navigates to its directory.
class _Crumb extends StatefulWidget {
  const _Crumb({
    super.key,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<_Crumb> createState() => _CrumbState();
}

class _CrumbState extends State<_Crumb> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final color = _hover && widget.enabled
        ? theme.labelPrimary
        : theme.color('--dsw-alias-label-tertiary');
    final text = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: DshChromeText(
        widget.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme
            .textStyle('--dsw-font-xs-13')
            .copyWith(
              color: color,
              height: 20 / 13,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: widget.enabled,
        mouseCursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onPressed : null,
          child: DshDecoratedBox(
            decoration: BoxDecoration(
              // The trail scrolls, so the ring stays inside the crumb.
              border: Border.all(
                color: _focus
                    ? theme.color('--dsw-alias-state-business-primary')
                    : const Color(0x00000000),
                width: theme.number('--dsw-focus-ring-width'),
              ),
              borderRadius: BorderRadius.circular(theme.radiusSm),
            ),
            child: text,
          ),
        ),
      ),
    );
  }
}

/// The fixed-label "Show hidden files" toggle; the pressed state seats a
/// trailing check so the label never shifts.
class _HiddenToggle extends StatefulWidget {
  const _HiddenToggle({
    required this.label,
    required this.on,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool on;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<_HiddenToggle> createState() => _HiddenToggleState();
}

class _HiddenToggleState extends State<_HiddenToggle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final color = !widget.enabled
        ? theme.color('--dsw-alias-label-caption')
        : (widget.on || _hover)
        ? theme.labelPrimary
        : theme.labelSecondary;
    return Semantics(
      toggled: widget.on,
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: widget.enabled,
        mouseCursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: GestureDetector(
          key: const ValueKey('directory-show-hidden'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onPressed : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: DshChromeText(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme
                        .textStyle('--dsw-font-xs-13')
                        .copyWith(
                          color: color,
                          height: 20 / 13,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
                if (widget.on) ...[
                  const SizedBox(width: 4),
                  DshIcon(DshIcons.check, size: 14, color: color),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One column of folder rows (dsh `LevelColumn`).
class _Level extends StatelessWidget {
  const _Level({
    super.key,
    required this.listing,
    required this.selectedPath,
    required this.busy,
    required this.onPick,
    required this.showHidden,
    required this.filterPrefix,
    required this.pathEditing,
  });

  final DirectoryListing listing;
  final String? selectedPath;
  final bool busy;
  final void Function(DirectoryEntry entry) onPick;
  final bool showHidden;
  final String? filterPrefix;
  final bool pathEditing;

  @override
  Widget build(BuildContext context) {
    final rows = visibleEntries(
      listing.entries,
      selectedPath,
      showHidden,
      filterPrefix,
    );
    return Padding(
      // The themed scrollbar's clearance on a wide window.
      padding: const EdgeInsets.only(right: 8),
      child: ListView.separated(
        key: ValueKey('directory-level-${listing.path}'),
        padding: EdgeInsets.zero,
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 2),
        itemBuilder: (context, i) => _Row(
          key: ValueKey('row-${rows[i].path}'),
          entry: rows[i],
          selected: rows[i].path == selectedPath,
          busy: busy,
          onPressed: () => onPick(rows[i]),
        ),
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    super.key,
    required this.entry,
    required this.selected,
    required this.busy,
    required this.onPressed,
  });

  final DirectoryEntry entry;
  final bool selected;
  final bool busy;
  final VoidCallback onPressed;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final selected = widget.selected;
    final fill = selected
        ? theme.color('--dsw-alias-interactive-bg-active')
        : _hover && !widget.busy
        ? theme.color('--dsw-alias-interactive-bg-hover')
        : null;
    return Semantics(
      button: true,
      selected: selected,
      enabled: !widget.busy,
      label: widget.entry.name,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: !widget.busy,
        mouseCursor: widget.busy
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
          SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
          SingleActivator(LogicalKeyboardKey.arrowRight): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.busy ? null : widget.onPressed,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: 28),
            child: DshDecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(theme.radiusSm),
                // The column scrolls and carries no left padding: the ring
                // stays inside the row.
                border: _focus
                    ? Border.all(
                        color: theme.color(
                          '--dsw-alias-state-business-primary',
                        ),
                        width: theme.number('--dsw-focus-ring-width'),
                      )
                    : null,
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    DshIcon(
                      selected ? DshIcons.folderOpen : DshIcons.folderClose,
                      size: 16,
                      color: selected
                          ? theme.color('--dsw-alias-button-info-fill')
                          : theme.labelSecondary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: DshChromeText(
                        widget.entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme
                            .textStyle('--dsw-font-xs-13')
                            .copyWith(
                              color: theme.labelPrimary,
                              height: 20 / 13,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    DshIcon(
                      DshIcons.chevronRight,
                      size: 12,
                      color: theme.color('--dsw-alias-label-tertiary'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The nested create dialog (dsh figma 813:23278): names one folder inside
/// the target.
class CreateFolderForm extends StatefulWidget {
  const CreateFolderForm({super.key, required this.model, required this.i18n});

  final DirectoryBrowserModel model;
  final DshI18n i18n;

  @override
  State<CreateFolderForm> createState() => _CreateFolderFormState();
}

class _CreateFolderFormState extends State<CreateFolderForm> {
  final TextEditingController _name = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'directory-folder-name');
  StreamSubscription<BrowserState>? _sub;
  bool _closed = false;
  ModalRoute<Object?>? _route;

  DirectoryBrowserModel get _m => widget.model;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void initState() {
    super.initState();
    _name.text = _m.value.folderDraft ?? '';
    _sub = _m.state.changes.listen((s) {
      if (!mounted) return;
      if (s.folderDraft == null) {
        // Created (the browser landed on it) or cancelled: the dialog ends,
        // once, whatever else the model goes on to publish.
        if (_closed) return;
        _closed = true;
        final route = _route;
        final navigator = route?.navigator;
        if (route != null && navigator != null && route.isActive) {
          navigator.removeRoute(route);
        }
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t(_ns, key, params: params);

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final s = _m.value;
    final creating = s.creatingFolder;
    final draft = s.folderDraft ?? '';
    final canCreate = !creating && draft.trim().isNotEmpty;
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DshChromeText(
            _t('browser.newFolder'),
            style: theme
                .textStyle('--dsw-font-base-strong-16')
                .copyWith(color: theme.labelPrimary, height: 24 / 16),
          ),
          const SizedBox(height: 12),
          DshChromeText(
            _t('browser.createIn', {'name': _m.targetName}),
            key: const ValueKey('directory-create-in'),
            style: theme
                .textStyle('--dsw-font-s-14')
                .copyWith(color: theme.labelPrimary, height: 22 / 14),
          ),
          const SizedBox(height: 12),
          _NameField(
            controller: _name,
            focusNode: _focus,
            placeholder: _t('browser.untitledFolder'),
            label: _t('browser.folderName'),
            enabled: !creating,
            onChanged: _m.setFolderDraft,
            onSubmitted: (_) => unawaited(_m.confirmCreate()),
          ),
          if (s.createError != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: DshChromeText(
                s.createError!,
                key: const ValueKey('directory-create-error'),
                style: theme
                    .textStyle('--dsw-font-xxs-12')
                    .copyWith(
                      color: theme.color('--dsw-alias-state-error-primary'),
                      height: 18 / 12,
                    ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              DshButton(
                key: const ValueKey('directory-create-cancel'),
                variant: DshButtonVariant.outline,
                onPressed: creating ? null : _m.cancelCreate,
                child: Text(_t('browser.cancel')),
              ),
              DshButton(
                key: const ValueKey('directory-create-confirm'),
                variant: DshButtonVariant.primary,
                onPressed: canCreate
                    ? () => unawaited(_m.confirmCreate())
                    : null,
                child: Text(_t('browser.create')),
              ),
            ],
          ),
        ],
      ),
    );
    return PopScope(
      canPop: !creating,
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape &&
              !creating) {
            _m.cancelCreate();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: body,
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    required this.label,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String placeholder;
  final String label;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final style = theme
        .textStyle('--dsw-font-s-14')
        .copyWith(color: theme.labelPrimary, height: 22 / 14);
    return DshDecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.color('--dsw-alias-border-l4'),
          width: dshHairlineOf(context),
        ),
        borderRadius: BorderRadius.circular(theme.radiusLg),
      ),
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Semantics(
            textField: true,
            label: label,
            child: TextField(
              key: const ValueKey('directory-folder-name'),
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              autofocus: true,
              maxLines: 1,
              style: style,
              cursorColor: theme.labelPrimary,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: placeholder,
                hintStyle: style.copyWith(
                  color: theme.color('--dsw-alias-label-caption'),
                ),
              ),
              onChanged: onChanged,
              onSubmitted: onSubmitted,
            ),
          ),
        ),
      ),
    );
  }
}
