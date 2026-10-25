import 'dart:math' as math;
import 'dart:async';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'chat_preferences.dart';
import 'process_layout.dart';

/// Focus belongs to the rendered chat, keeping the conversation/slot layers
/// independent of Flutter while preserving a control across recentering.
class TurnProcessFocusScope extends InheritedWidget {
  const TurnProcessFocusScope({
    super.key,
    required this.focusNode,
    required super.child,
  });
  final FocusNode focusNode;
  static FocusNode? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TurnProcessFocusScope>()
      ?.focusNode;
  @override
  bool updateShouldNotify(TurnProcessFocusScope oldWidget) =>
      oldWidget.focusNode != focusNode;
}

/// Fixed Turn duration; partial history never invents an opening timestamp.
class TurnProcessView extends StatelessWidget {
  const TurnProcessView({
    super.key,
    required this.node,
    required this.i18n,
    this.controls,
  });
  final ViewNode node;
  final DshI18n i18n;
  final TurnProcessControls? controls;
  @override
  Widget build(BuildContext context) {
    final turn = owningTurn(node.location);
    if (turn?.status != BoundaryStatus.closed) return const SizedBox.shrink();
    final reason = (turn!.end?.data['reason'] as Map?)?['kind'];
    final stopped = reason == 'aborted' || reason == 'interrupted';
    final failed = reason == 'error';
    String t(String key) => i18n.t('chat', key);
    final elapsed = turn.start == null || turn.end == null || stopped || failed
        ? null
        : math.max(1000, turn.end!.time - turn.start!.time);
    final label = stopped
        ? t('message.stopped')
        : failed
        ? t('message.turnProcess.failed')
        : elapsed == null
        ? t('message.turnProcess.worked')
        : t('message.turnProcess.took');
    final canCollapse =
        controls?.foldable == true &&
        controls?.hasContent == true &&
        !turnProcessAlwaysOpen(node);
    final open = controls == null || !controls!.foldable || controls!.open;
    final theme = context.dsh;
    final style = theme
        .textStyle('--dsw-font-s-14')
        .copyWith(
          color: theme.color('--dsw-alias-label-tertiary'),
          height: 24 / 14,
        );
    final duration = <InlineSpan>[];
    if (elapsed != null) {
      final total = elapsed ~/ 1000;
      void part(int value, String key) {
        duration.add(
          TextSpan(
            text: '$value',
            style: theme
                .fixedCodeStyle(size: style.fontSize ?? 14, line: 24)
                .copyWith(color: style.color),
          ),
        );
        duration.add(TextSpan(text: t(key)));
      }

      if (total >= 3600) part(total ~/ 3600, 'duration.hourUnit');
      if (total >= 60) part(total ~/ 60 % 60, 'duration.minuteUnit');
      part(total % 60, 'duration.secondUnit');
    }
    return _ProcessButton(
      key: ValueKey('turn-process-${(node.data! as TurnProcessData).turn}'),
      enabled: canCollapse,
      focusNode: TurnProcessFocusScope.maybeOf(context),
      expanded: controls?.hasContent == true ? open : null,
      onPressed: () => controls?.setOpen(!open),
      child: DshContainer(
        height: 33,
        padding: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.color('--dsw-alias-border-l2'),
              width: dshBorderWidthOf(context, .5),
            ),
          ),
        ),
        child: Row(
          children: [
            Flexible(
              child: RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: style,
                  children: [
                    TextSpan(text: label),
                    ...duration,
                  ],
                ),
              ),
            ),
            if (canCollapse) ...[
              const SizedBox(width: 4),
              DshIcon(
                open ? DshIcons.chevronUp : DshIcons.chevronDown,
                size: 14,
                color: style.color,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ProcessGroupView extends StatefulWidget {
  const ProcessGroupView({
    super.key,
    required this.group,
    required this.preferences,
    required this.i18n,
    required this.open,
    required this.onToggle,
    required this.buildMember,
    this.deferCollapse = false,
  });
  final ProcessGroup group;
  final ChatPreferences preferences;
  final DshI18n i18n;
  final bool open, deferCollapse;
  final VoidCallback onToggle;
  final Widget Function(ProcessMember) buildMember;
  @override
  State<ProcessGroupView> createState() => _ProcessGroupViewState();
}

class _ProcessGroupViewState extends State<ProcessGroupView> {
  bool _hover = false;
  final _bodyScroll = ScrollController();
  bool _fadeTop = false, _fadeBottom = false, _following = true;
  @override
  void initState() {
    super.initState();
    _bodyScroll.addListener(_sampleEdges);
  }

  void _sampleEdges() {
    if (!_bodyScroll.hasClients || !_bodyScroll.position.hasContentDimensions) {
      return;
    }
    final top = _bodyScroll.offset > 1;
    final bottom =
        _bodyScroll.offset < _bodyScroll.position.maxScrollExtent - 1;
    _following = !bottom;
    if (mounted && (top != _fadeTop || bottom != _fadeBottom)) {
      setState(() {
        _fadeTop = top;
        _fadeBottom = bottom;
      });
    }
  }

  @override
  void didUpdateWidget(ProcessGroupView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasOpen = oldWidget.open;
    final maxBefore =
        _bodyScroll.hasClients && _bodyScroll.position.hasContentDimensions
        ? _bodyScroll.position.maxScrollExtent
        : null;
    final offsetBefore = _bodyScroll.hasClients ? _bodyScroll.offset : 0.0;
    final firstOld = oldWidget.group.members.first.key;
    final prepended =
        widget.group.members.indexWhere((m) => m.key == firstOld) > 0;
    final follow = _following;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_bodyScroll.hasClients ||
          !_bodyScroll.position.hasContentDimensions) {
        return;
      }
      final max = _bodyScroll.position.maxScrollExtent;
      if (!wasOpen && widget.open) {
        _bodyScroll.jumpTo(widget.group.closed ? 0 : max);
      } else if (prepended && maxBefore != null) {
        _bodyScroll.jumpTo((offsetBefore + max - maxBefore).clamp(0, max));
      } else if (follow && !widget.group.closed) {
        _bodyScroll.jumpTo(max);
      }
      _sampleEdges();
    });
  }

  String? _liveTitle, _nextTitle;
  DateTime? _published;
  Timer? _titleTimer;
  String _retainLive(String proposed) {
    final now = DateTime.now();
    if (_liveTitle == null ||
        now.difference(_published!).inMilliseconds >= 150) {
      _liveTitle = proposed;
      _published = now;
      _titleTimer?.cancel();
      _titleTimer = null;
    } else if (_liveTitle != proposed) {
      _nextTitle = proposed;
      _titleTimer ??= Timer(
        Duration(
          milliseconds: 150 - now.difference(_published!).inMilliseconds,
        ),
        () {
          _titleTimer = null;
          if (!mounted) return;
          setState(() {
            _liveTitle = _nextTitle;
            _published = DateTime.now();
          });
        },
      );
    }
    return _liveTitle!;
  }

  @override
  void dispose() {
    _titleTimer?.cancel();
    _bodyScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group, prefs = widget.preferences;
    final history =
        owningTurn(g.members.first.node.location)?.status !=
            BoundaryStatus.open &&
        !widget.deferCollapse;
    final grouped =
        prefs.mode.value != TranscriptViewMode.verbose &&
        (prefs.mode.value != TranscriptViewMode.detailed || history);
    final open = !grouped || widget.open;
    final activity = ProcessActivity(g.members);
    String t(String key, [Map<String, Object?> params = const {}]) =>
        widget.i18n.t('chat', key, params: params);
    String title;
    if (g.closed) {
      final kinds = activity.ranked;
      final labels = kinds
          .take(3)
          .map((k) => t('message.stepProcess.done.$k'))
          .toList();
      if (labels.isEmpty) {
        title = t('message.stepProcess.done.thinking');
      } else if (labels.length == 2) {
        final prefix = t('message.stepProcess.sharedPrefix');
        var second = labels[1];
        if (prefix.isNotEmpty &&
            labels[0].startsWith(prefix) &&
            second.startsWith(prefix)) {
          second = second.substring(prefix.length);
        }
        if (second.isNotEmpty) {
          second = second[0].toLowerCase() + second.substring(1);
        }
        title = t('message.stepProcess.joinTwo', {
          'first': labels[0],
          'second': second,
        });
      } else {
        title = labels
            .asMap()
            .entries
            .map(
              (e) => e.key == 0
                  ? e.value
                  : e.value[0].toLowerCase() + e.value.substring(1),
            )
            .join(t('message.stepProcess.comma'));
        if (kinds.length > 3) {
          title = t('message.stepProcess.more', {'title': title});
        }
      }
    } else {
      title = t(
        'message.stepProcess.${activity.preparing ? 'prepare.' : ''}${activity.running ?? 'thinking'}',
      );
      if (prefs.liveDetail && activity.detail.isNotEmpty) {
        title += '${t('message.turnProcess.separator')}${activity.detail}';
      }
      title = _retainLive(title);
    }
    final kind = g.closed
        ? activity.ranked.firstOrNull ?? 'thinking'
        : activity.running ?? 'thinking';
    final glyph = switch (kind) {
      'thinking' => DshShellIcons.think,
      'read' || 'readImage' || 'webFetch' => DshIcons.browse,
      'search' => DshIcons.search,
      'edit' || 'write' => DshIcons.edit,
      'commands' => DshIcons.api,
      'code' => DshIcons.code,
      'webSearch' => DshIcons.globe,
      'subagents' => DshIcons.agentPreset,
      'plan' => DshIcons.plan,
      'questions' => DshIcons.question,
      _ => DshIcons.sparkle,
    };
    final theme = context.dsh;
    final baseStyle = theme.textStyle('--dsw-font-s-14');
    final color = theme.color(
      _hover ? '--dsw-alias-label-secondary' : '--dsw-alias-label-tertiary',
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < g.members.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          KeyedSubtree(
            key: ValueKey(g.members[i].key),
            child: widget.buildMember(g.members[i]),
          ),
        ],
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Offstage(
          offstage: !grouped,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: _ProcessButton(
              enabled: grouped,
              expanded: open,
              onPressed: widget.onToggle,
              child: Padding(
                padding: EdgeInsets.only(bottom: open ? 8 : 0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        child: DshIcon(
                          open
                              ? DshIcons.chevronUp
                              : _hover
                              ? DshIcons.chevronDown
                              : glyph,
                          size: 14,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: DshShimmer(
                          active: !g.closed,
                          child: DshChromeText(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: baseStyle.fontSize,
                              color: color,
                              fontFamily: baseStyle.fontFamily,
                              fontFamilyFallback: baseStyle.fontFamilyFallback,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0,
                            ),
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
        Offstage(
          offstage: !open,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: grouped
                  ? math.min(400, MediaQuery.sizeOf(context).height / 2)
                  : double.infinity,
            ),
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) {
                final edge = bounds.height <= 0
                    ? 0.0
                    : math.min(.5, 24 / bounds.height);
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    grouped && _fadeTop
                        ? theme.labelPrimary.withValues(alpha: 0)
                        : theme.labelPrimary.withValues(alpha: 1),
                    theme.labelPrimary.withValues(alpha: 1),
                    theme.labelPrimary.withValues(alpha: 1),
                    grouped && _fadeBottom
                        ? theme.labelPrimary.withValues(alpha: 0)
                        : theme.labelPrimary.withValues(alpha: 1),
                  ],
                  stops: [0, edge, 1 - edge, 1],
                ).createShader(bounds);
              },
              child: SingleChildScrollView(
                controller: _bodyScroll,
                primary: false,
                physics: grouped ? null : const NeverScrollableScrollPhysics(),
                child: content,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProcessButton extends StatefulWidget {
  const _ProcessButton({
    super.key,
    required this.enabled,
    required this.expanded,
    required this.onPressed,
    required this.child,
    this.focusNode,
  });
  final FocusNode? focusNode;
  final bool enabled;
  final bool? expanded;
  final VoidCallback onPressed;
  final Widget child;
  @override
  State<_ProcessButton> createState() => _ProcessButtonState();
}

class _ProcessButtonState extends State<_ProcessButton> {
  final _ownedFocus = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;
  @override
  void dispose() {
    _ownedFocus.dispose();
    super.dispose();
  }

  void _activate() {
    _focus.requestFocus();
    DshDisclosureChange(!(widget.expanded ?? false), context).dispatch(context);
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: widget.enabled,
    expanded: widget.expanded,
    child: FocusableActionDetector(
      focusNode: _focus,
      enabled: widget.enabled,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? _activate : null,
        child: widget.child,
      ),
    ),
  );
}
