import 'dart:async';

import 'package:dsh_client/generated.dart' as session_ns;
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show showModalBottomSheet;
import 'package:flutter/widgets.dart';

import 'model_directory.dart';
import 'provider_order.dart';

const String _ns = 'model';

/// The composer's model seat (dsh `ModelSelect`, slot
/// `conversation.input.model`): a chip with the current model's name and
/// reasoning effort that opens a sheet. The sheet is the phone form of dsh's
/// two-level menu: a root with the Model and Effort rows, each drilling into
/// its list; the model list is provider-grouped, searchable above four
/// models, and shows provider-local failures with a retry.
class ModelSeat extends StatefulWidget {
  const ModelSeat({
    super.key,
    required this.directory,
    required this.i18n,
    this.locked = false,
  });

  final ModelDirectory directory;
  final DshI18n i18n;

  /// Whether the session takes no changes (a running turn is not a reason:
  /// the new model applies to the next request).
  final bool locked;

  @override
  State<ModelSeat> createState() => _ModelSeatState();
}

class _ModelSeatState extends State<ModelSeat> {
  String _t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t(_ns, key, params: params);

  Future<void> _open() async {
    unawaited(
      widget.directory.load().then<void>((_) {}, onError: (Object _) {}),
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.dsh.color('--dsw-alias-bg-layer-2'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (_) =>
          ModelSheet(directory: widget.directory, i18n: widget.i18n),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DshWatch(
      changes: widget.directory.state.changes,
      builder: (context) {
        final theme = context.dsh;
        final state = widget.directory.state.value;
        final view = _View.of(state, _t);
        final waiting =
            view.choice == null && state.status == ModelDirectoryStatus.loading;
        final modelLabel = waiting
            ? _t('trigger.loading')
            : (view.choice?.model.name ?? _t('trigger.fallback'));
        final effort = view.effortLabel;
        final aria = waiting
            ? _t('trigger.loading')
            : view.choice == null
            ? _t('trigger.selectAria')
            : effort == null
            ? _t('trigger.aria', {'model': modelLabel})
            : _t('trigger.ariaEffort', {'model': modelLabel, 'effort': effort});
        final busy = state.pending != null;
        final style = theme
            .textStyle('--dsw-font-xs-13')
            .copyWith(
              color: widget.locked
                  ? theme.color('--dsw-alias-label-dimmed')
                  : theme.labelSecondary,
              height: 20 / 13,
              fontWeight: FontWeight.w400,
            );
        return Semantics(
          button: true,
          enabled: !widget.locked,
          label: aria,
          excludeSemantics: true,
          child: GestureDetector(
            key: const ValueKey('model-chip'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.locked ? null : _open,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260, minHeight: 28),
              child: Padding(
                padding: const EdgeInsets.only(left: 8, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: DshChromeText(
                        modelLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      ),
                    ),
                    if (effort != null) ...[
                      const SizedBox(width: 4),
                      Flexible(
                        flex: 0,
                        child: DshChromeText(
                          effort,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: style.copyWith(
                            color: theme.color('--dsw-alias-label-caption'),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    if (busy)
                      const DshStatusDot(DshStatus.running)
                    else
                      DshIcon(
                        DshIcons.chevronDown,
                        color: theme.color('--dsw-alias-label-caption'),
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

/// The content of the model sheet.
class ModelSheet extends StatefulWidget {
  const ModelSheet({super.key, required this.directory, required this.i18n});

  final ModelDirectory directory;
  final DshI18n i18n;

  @override
  State<ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<ModelSheet> {
  _Pane _pane = _Pane.root;
  bool _paneChosen = false;
  String _query = '';
  String? _toast;
  bool _lastWasLoad = true;
  Timer? _toastTimer;

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  String _t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t(_ns, key, params: params);

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
      Navigator.of(context).pop();
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

  void _chooseModel(_View view, _Choice c) {
    final current = view.state.current;
    if (current?.provider == c.group.id && current?.model == c.model.id) {
      Navigator.of(context).pop();
      return;
    }
    final defaultEffort = c.model.reasoning?.defaultEffort;
    unawaited(
      _submit(
        session_ns.ModelSelection(
          provider: c.group.id,
          model: c.model.id,
          reasoningEffort: defaultEffort,
        ),
      ),
    );
  }

  void _chooseEffort(_View view, _EffortChoice level) {
    final current = view.state.current;
    if (current == null) return;
    if (view.effective == level.effort) {
      Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return SafeArea(
      child: DshWatch(
        changes: widget.directory.state.changes,
        builder: (context) {
          final view = _View.of(widget.directory.state.value, _t);
          // With nothing selected the sheet opens on the model list.
          final pane = !_paneChosen && view.choice == null
              ? _Pane.model
              : _pane;
          return Column(
            key: const ValueKey('model-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(theme, view, pane),
              Flexible(
                child: switch (pane) {
                  _Pane.root => _root(theme, view),
                  _Pane.model => _models(theme, view),
                  _Pane.effort => _effortList(theme, view),
                },
              ),
              if (_toast != null) _banner(theme, _toast!, null),
            ],
          );
        },
      ),
    );
  }

  Widget _header(DshThemeData theme, _View view, _Pane pane) {
    final title = switch (pane) {
      _Pane.root => _t('menu.aria'),
      _Pane.model => _t('menu.model'),
      _Pane.effort => _t('menu.effort'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DshSpace.sm,
        DshSpace.sm,
        DshSpace.lg,
        0,
      ),
      child: Row(
        children: [
          if (pane != _Pane.root && view.choice != null)
            GestureDetector(
              key: const ValueKey('model-back'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                _pane = _Pane.root;
                _paneChosen = true;
                _query = '';
              }),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: Transform.rotate(
                    angle: 3.14159265,
                    child: DshIcon(
                      DshIcons.chevronRight,
                      color: theme.labelSecondary,
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: DshSpace.sm),
          Expanded(
            child: DshChromeText(
              title,
              style: theme
                  .textStyle('--dsw-font-s-strong-14')
                  .copyWith(color: theme.labelSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(
    DshThemeData theme,
    Key key,
    String label,
    String value,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: DshSpace.touch + 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DshSpace.lg),
          child: Row(
            children: [
              DshChromeText(
                label,
                style: theme
                    .textStyle('--dsw-font-base-16')
                    .copyWith(color: theme.labelPrimary),
              ),
              const SizedBox(width: DshSpace.md),
              Expanded(
                child: DshChromeText(
                  value,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme
                      .textStyle('--dsw-font-base-16')
                      .copyWith(color: theme.labelSecondary),
                ),
              ),
              const SizedBox(width: 4),
              DshIcon(
                DshIcons.chevronRight,
                color: theme.color('--dsw-alias-label-caption'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _root(DshThemeData theme, _View view) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _cell(
          theme,
          const ValueKey('model-root-model'),
          _t('menu.model'),
          view.choice?.model.name ?? _t('trigger.fallback'),
          () => setState(() {
            _pane = _Pane.model;
            _paneChosen = true;
          }),
        ),
        if (view.reasoning != null)
          _cell(
            theme,
            const ValueKey('model-root-effort'),
            _t('menu.effort'),
            view.effortLabel ?? '',
            () => setState(() {
              _pane = _Pane.effort;
              _paneChosen = true;
            }),
          ),
      ],
    );
  }

  Widget _banner(DshThemeData theme, String text, VoidCallback? retry) {
    return Container(
      key: const ValueKey('model-banner'),
      margin: const EdgeInsets.fromLTRB(
        DshSpace.md,
        DshSpace.xs,
        DshSpace.md,
        DshSpace.xs,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: DshSpace.md,
        vertical: DshSpace.sm,
      ),
      decoration: theme.cornerDecoration(
        theme.radiusSm,
        color: theme.color('--dsw-alias-state-warn-tertiary'),
      ),
      child: Row(
        children: [
          DshIcon(
            DshIcons.warning,
            size: 16,
            color: theme.color('--dsw-alias-state-warn-primary'),
          ),
          const SizedBox(width: DshSpace.sm),
          Expanded(
            child: DshChromeText(
              text,
              style: theme
                  .textStyle('--dsw-font-xxs-12')
                  .copyWith(color: theme.labelPrimary),
            ),
          ),
          if (retry != null)
            GestureDetector(
              key: const ValueKey('model-retry'),
              behavior: HitTestBehavior.opaque,
              onTap: retry,
              child: Padding(
                padding: const EdgeInsets.only(left: DshSpace.sm),
                child: DshChromeText(
                  widget.i18n.t('common', 'retry'),
                  style: theme
                      .textStyle('--dsw-font-xxs-strong-12')
                      .copyWith(color: theme.focusRingColor),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(
    DshThemeData theme, {
    required Key key,
    required String label,
    required bool selected,
    required bool pending,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: DshSpace.touch),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: DshSpace.lg),
            child: Row(
              children: [
                Expanded(
                  child: DshChromeText(
                    label,
                    style: theme
                        .textStyle('--dsw-font-base-16')
                        .copyWith(color: theme.labelPrimary),
                  ),
                ),
                SizedBox(
                  width: 24,
                  child: Center(
                    child: pending
                        ? const DshStatusDot(DshStatus.running)
                        : (selected
                              ? DshIcon(
                                  DshIcons.check,
                                  size: 16,
                                  color: theme.labelPrimary,
                                )
                              : null),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _models(DshThemeData theme, _View view) {
    final state = view.state;
    final busy = state.pending != null;
    final showSearch = view.showSearch;
    final query = showSearch ? _query.trim() : '';
    final groups = [
      for (final g in view.groups)
        (group: g, models: rankByName(g.models, query, name: (m) => m.name)),
    ].where((e) => e.models.isNotEmpty).toList();
    final current = state.current;
    final accountName = _t('provider.account');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DshSpace.md,
              DshSpace.sm,
              DshSpace.md,
              DshSpace.xs,
            ),
            child: _Search(
              key: const ValueKey('model-search'),
              value: _query,
              placeholder: _t('search.placeholder'),
              clearLabel: _t('search.clear'),
              enabled: !busy,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        if (state.status == ModelDirectoryStatus.loading)
          _note(theme, _t('status.loading')),
        if (state.error != null && _lastWasLoad)
          _banner(theme, _t('error.action', {'message': state.error}), _reload),
        for (final f in state.failures)
          _banner(
            theme,
            _t('warning.groupLoad', {
              'name': f.id == 'deepseek-account' ? accountName : f.name,
              'message': f.message,
            }),
            _reload,
          ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              for (final e in groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DshSpace.lg,
                    DshSpace.sm,
                    DshSpace.lg,
                    DshSpace.xs,
                  ),
                  child: DshChromeText(
                    e.group.id == 'deepseek-account'
                        ? accountName
                        : e.group.name,
                    key: ValueKey('model-group-${e.group.id}'),
                    style: theme
                        .textStyle('--dsw-font-xs-strong-13')
                        .copyWith(
                          color: theme.color('--dsw-alias-label-tertiary'),
                        ),
                  ),
                ),
                for (final m in e.models)
                  _row(
                    theme,
                    key: ValueKey('model-option-${e.group.id}/${m.id}'),
                    label: m.name,
                    selected:
                        current?.provider == e.group.id &&
                        current?.model == m.id,
                    pending:
                        state.pending?.provider == e.group.id &&
                        state.pending?.model == m.id,
                    enabled: !busy,
                    onTap: () => _chooseModel(view, _Choice(e.group, m)),
                  ),
              ],
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

  Widget _note(DshThemeData theme, String text) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: DshSpace.lg,
      vertical: DshSpace.md,
    ),
    child: DshChromeText(
      text,
      style: theme
          .textStyle('--dsw-font-s-14')
          .copyWith(color: theme.color('--dsw-alias-label-tertiary')),
    ),
  );

  Widget _effortList(DshThemeData theme, _View view) {
    final state = view.state;
    final pending = state.pending;
    final current = state.current;
    if (view.efforts.isEmpty) return _note(theme, _t('empty.efforts'));
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: [
        if (state.error != null && _lastWasLoad)
          _banner(theme, _t('error.action', {'message': state.error}), _reload),
        for (final level in view.efforts)
          _row(
            theme,
            key: ValueKey('effort-option-${level.key}'),
            label: level.label,
            selected: view.effective == level.effort,
            pending:
                pending != null &&
                pending.provider == current?.provider &&
                pending.model == current?.model &&
                pending.reasoningEffort == level.effort,
            enabled: pending == null,
            onTap: () => _chooseEffort(view, level),
          ),
      ],
    );
  }
}

class _Search extends StatefulWidget {
  const _Search({
    super.key,
    required this.value,
    required this.placeholder,
    required this.clearLabel,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final String placeholder;
  final String clearLabel;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  State<_Search> createState() => _SearchState();
}

class _SearchState extends State<_Search> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        DshTextField(
          controller: _controller,
          placeholder: widget.placeholder,
          enabled: widget.enabled,
          onChanged: widget.onChanged,
        ),
        if (widget.value.isNotEmpty)
          Semantics(
            button: true,
            label: widget.clearLabel,
            excludeSemantics: true,
            child: GestureDetector(
              key: const ValueKey('model-search-clear'),
              behavior: HitTestBehavior.opaque,
              onTap: widget.enabled
                  ? () {
                      _controller.clear();
                      widget.onChanged('');
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(DshSpace.md),
                child: DshIcon(
                  DshIcons.closeFill,
                  size: 14,
                  color: theme.color('--dsw-alias-label-caption'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
