import 'dart:async';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/dsh_theme.dart' show DshThemeData;
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'popup_controller.dart';

const double _maxHeight = 320;

/// The popupSelect shell (dsh `PopupSelectView`): one session's
/// [PopupSelectController] drawn above the composer. Unlike the candidate menu
/// it HOLDS focus while open: the search field takes the keyboard, typing
/// filters the loaded options locally, up and down walk them (wrapping), Enter
/// and Tab accept the highlight, Escape and Shift+Tab return to the composer.
/// A press outside the card and the composer dismisses it.
class PopupSelectOverlay extends StatefulWidget {
  const PopupSelectOverlay({
    super.key,
    required this.sessionId,
    required this.controller,
    required this.i18n,
  });

  final String sessionId;
  final PopupSelectController controller;
  final DshI18n i18n;

  @override
  State<PopupSelectOverlay> createState() => _PopupSelectOverlayState();
}

class _PopupSelectOverlayState extends State<PopupSelectOverlay> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _focus = FocusNode();
  StreamSubscription<PopupState>? _sub;
  final Map<int, GlobalKey> _rowKeys = {};
  bool _wasOpen = false;
  int _scrolled = -1;
  bool _confirmShown = false;

  PopupSelectController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _sub = _c.state.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t('command', key, params: params);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final s = _c.state.value;
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (key == LogicalKeyboardKey.arrowDown) {
      _c.move(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _c.move(-1);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      unawaited(_c.select(s.active));
    } else if (key == LogicalKeyboardKey.tab) {
      final rows = filterOptions(s.options, s.search, s.searchMode);
      // With nothing to settle the keystroke stays the platform's, which is how
      // the error strip's retry stays reachable.
      if (!shift && (s.status != PopupStatus.ready || rows.isEmpty)) {
        return KeyEventResult.ignored;
      }
      if (shift) {
        _c.dismiss(focus: true);
      } else {
        unawaited(_c.select(s.active));
      }
    } else if (key == LogicalKeyboardKey.escape) {
      _c.dismiss(focus: true);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final s = _c.state.value;
    if (!s.open) {
      _wasOpen = false;
      _confirmShown = false;
      _scrolled = -1;
      if (_search.text.isNotEmpty) _search.clear();
      return const SizedBox.shrink();
    }
    final theme = context.dsh;
    if (!_wasOpen) {
      _wasOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
    if (s.confirming != null && !_confirmShown) {
      _confirmShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _confirm(s));
    }
    if (s.confirming == null) _confirmShown = false;
    final rows = filterOptions(s.options, s.search, s.searchMode);
    final groups = groupOptions(rows);
    var index = 0;
    if (s.active != _scrolled) {
      _scrolled = s.active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _rowKeys[s.active]?.currentContext;
        if (ctx != null && ctx.mounted) {
          unawaited(
            Scrollable.ensureVisible(
              ctx,
              alignment: 0.5,
              duration: Duration.zero,
            ),
          );
        }
      });
    }
    final emptyLabel = s.searchLabels == null
        ? _t('status.empty')
        : s.options.isEmpty
        ? s.searchLabels!.empty
        : s.searchLabels!.noResults;
    final tertiary = theme.color('--dsw-alias-label-tertiary');
    final body = <Widget>[
      if (s.error != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          child: Row(
            key: const ValueKey('popup-error'),
            children: [
              Expanded(
                child: DshChromeText(
                  s.error!,
                  style: theme
                      .textStyle('--dsw-font-xxxs-11')
                      .copyWith(
                        color: theme.color('--dsw-alias-state-error-primary'),
                        height: 15 / 11,
                      ),
                ),
              ),
              if (s.status == PopupStatus.failed)
                GestureDetector(
                  key: const ValueKey('popup-retry'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _c.retry,
                  child: DshContainer(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.color('--dsw-alias-border-inverted'),
                        width: dshBorderWidthOf(context, 0.5),
                      ),
                      borderRadius: BorderRadius.circular(theme.radiusSm),
                    ),
                    child: DshChromeText(
                      widget.i18n.t('command', 'retry'),
                      style: theme
                          .textStyle('--dsw-font-xxxs-11')
                          .copyWith(color: theme.labelPrimary, height: 15 / 11),
                    ),
                  ),
                ),
            ],
          ),
        ),
      if (s.status == PopupStatus.pending) _status(theme, _t('status.loading')),
      if (s.submitting) _status(theme, _t('status.applying')),
      if (s.status == PopupStatus.ready && rows.isEmpty)
        _status(theme, emptyLabel),
      if (s.status == PopupStatus.ready)
        Flexible(
          child: SingleChildScrollView(
            key: const ValueKey('popup-list'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final g in groups) ...[
                  if (g.group != null)
                    Padding(
                      // `.group + .group { margin-top: 3px }`.
                      padding: EdgeInsets.only(
                        top: identical(g, groups.first) ? 0 : 3,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(7, 4, 7, 2),
                        child: DshChromeText(
                          g.group!.label,
                          style: theme
                              .textStyle('--dsw-font-xxxs-11')
                              .copyWith(
                                color: tertiary,
                                height: 16 / 11,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ),
                    ),
                  for (final option in g.rows)
                    _optionRow(theme, option, index++, s.active),
                ],
              ],
            ),
          ),
        ),
    ];
    return TapRegion(
      groupId: composerTapGroup(widget.sessionId),
      onTapOutside: (_) => _c.dismiss(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cap = constraints.hasBoundedHeight
              ? constraints.maxHeight.clamp(0.0, _maxHeight)
              : _maxHeight;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: cap),
            child: DshMenuSurface(
              key: const ValueKey('command-popup-surface'),
              child: Semantics(
                label: _t('overlay.aria', {'command': '${s.command}'}),
                child: Column(
                  key: const ValueKey('command-popup'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Focus(
                      onKeyEvent: _onKey,
                      child: _SearchField(
                        controller: _search,
                        focusNode: _focus,
                        placeholder:
                            s.searchLabels?.placeholder ??
                            _t('search.placeholder'),
                        label: _t('search.aria'),
                        readOnly: s.submitting,
                        onChanged: _c.setSearch,
                      ),
                    ),
                    ...body,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _status(DshThemeData theme, String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    child: DshChromeText(
      text,
      style: theme
          .textStyle('--dsw-font-xxs-12')
          .copyWith(
            color: theme.color('--dsw-alias-label-tertiary'),
            height: 17 / 12,
          ),
    ),
  );

  Widget _optionRow(
    DshThemeData theme,
    SelectOption option,
    int index,
    int active,
  ) {
    final compact = MediaQuery.sizeOf(context).width < 768;
    final isActive = index == active;
    final key = _rowKeys.putIfAbsent(index, GlobalKey.new);
    return Semantics(
      key: key,
      button: true,
      selected: isActive,
      label: option.badge == null
          ? option.label
          : '${option.label} ${option.badge}',
      excludeSemantics: true,
      child: MouseRegion(
        onHover: isActive ? null : (_) => _c.highlight(index),
        child: GestureDetector(
          key: ValueKey('popup-option-${option.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_c.select(index)),
          child: DshDecoratedBox(
            decoration: BoxDecoration(
              color: isActive
                  ? theme.color('--dsw-alias-interactive-bg-hover')
                  : null,
              borderRadius: BorderRadius.circular(theme.radiusMd),
            ),
            child: ConstrainedBox(
              // dsh's rows are 5px + the 12px line + 5px; a phone row keeps the
              // 44px touch target.
              constraints: BoxConstraints(
                minHeight: compact ? DshSpace.touch : 0,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                child: Row(
                  children: [
                    Flexible(
                      flex: 0,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: option.label),
                            if (option.badge != null)
                              WidgetSpan(
                                alignment: PlaceholderAlignment.top,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: DshChromeText(
                                    option.badge!,
                                    style: theme
                                        .textStyle('--dsw-font-xxxs-11')
                                        // `.badge { font-size: 8px }`, below the ladder.
                                        .apply(fontSizeFactor: 8 / 11)
                                        .copyWith(
                                          height: 10 / 8,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.2,
                                          color: theme.color(
                                            '--dsw-alias-label-tertiary',
                                          ),
                                        ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme
                            .textStyle('--dsw-font-xxs-12')
                            .copyWith(
                              color: theme.labelPrimary,
                              height: 17 / 12,
                            ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: option.detail == null
                          ? const SizedBox.shrink()
                          : DshChromeText(
                              option.detail!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: theme
                                  .textStyle('--dsw-font-xxxs-11')
                                  .copyWith(
                                    color: theme.color(
                                      '--dsw-alias-label-tertiary',
                                    ),
                                    height: 15 / 11,
                                  ),
                            ),
                    ),
                    if (option.active) ...[
                      const SizedBox(width: 6),
                      DshIcon(
                        DshIcons.check,
                        size: 14,
                        color: theme.color('--dsw-alias-menu-icon'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirm(PopupState s) async {
    final option = s.confirming;
    if (option == null || !mounted) return;
    final confirmation = option.confirmation!;
    final confirmed = await showDshRiskDialog(
      context,
      title: confirmation.title,
      description: confirmation.description,
      acknowledgeLabel: confirmation.acknowledgeLabel,
      cancelLabel: confirmation.cancelLabel,
      closeLabel: widget.i18n.t('command', 'close'),
      confirmLabel: confirmation.confirmLabel,
    );
    if (!mounted) return;
    if (confirmed) {
      _c.acknowledge(true);
      await _c.confirm();
    } else {
      _c.cancelConfirmation();
    }
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    required this.label,
    required this.readOnly,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String placeholder;
  final String label;
  final bool readOnly;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final style = theme
        .textStyle('--dsw-font-xxs-12')
        .copyWith(color: theme.labelPrimary, height: 17 / 12);
    final compact = MediaQuery.sizeOf(context).width < 768;
    return Semantics(
      label: label,
      textField: true,
      // `.search { margin: 2px 2px 3px; padding: 5px 7px; border: .5px solid
      // transparent }`: transparent in both palettes, as dsh keeps it.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 3),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: compact ? 40 : 0),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 7 + dshBorderWidthOf(context, 0.5),
              vertical: 5 + dshBorderWidthOf(context, 0.5),
            ),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => Stack(
                children: [
                  if (controller.text.isEmpty)
                    IgnorePointer(
                      child: Text(
                        placeholder,
                        maxLines: 1,
                        style: style.copyWith(
                          color: theme.color('--dsw-alias-label-tertiary'),
                        ),
                      ),
                    ),
                  EditableText(
                    key: const ValueKey('popup-search'),
                    controller: controller,
                    focusNode: focusNode,
                    readOnly: readOnly,
                    style: style,
                    cursorColor: theme.focusRingColor,
                    backgroundCursorColor: theme.color(
                      '--dsw-alias-label-tertiary',
                    ),
                    onChanged: onChanged,
                    maxLines: 1,
                    textInputAction: TextInputAction.search,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
