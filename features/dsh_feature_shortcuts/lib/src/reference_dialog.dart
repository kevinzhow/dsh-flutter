/// The searchable, editable shortcut reference (dsh `ui-shortcuts`
/// `Reference.tsx`): a 480x600 modal listing every command with its keycaps,
/// grouped as dsh groups them, with inline recording and editing of a
/// binding, "restore all defaults" behind a confirmation, and failures shown as
/// a toast.
library;

import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'feedback.dart';
import 'key_codes.dart';

/// Core reference positions are independent of labels and registration order
/// (dsh `coreActionOrder`).
const List<String> coreActionOrder = [
  'shortcuts.open',
  'session.new',
  'sidebar.left.toggle',
  'session.search',
  'workspace.add',
  'session.rename',
  'session.fork',
  'session.archive',
  'settings.open',
  'fontSize.increase',
  'fontSize.decrease',
  'workspace.openLocal',
  'sidebar.right.toggle',
  'workspace.files',
  'browser.new',
  'terminal.new',
  'pane.split',
  'pane.fullscreen.toggle',
  'page.refresh',
  'page.close',
];

class _Row {
  _Row({
    required this.id,
    required this.label,
    required this.keys,
    required this.names,
    required this.group,
    this.entry,
  });

  final String id;
  final String label;
  final List<String> keys;
  final List<String> names;
  final ShortcutGroup group;

  /// The editable catalog row; null for a fixed (read-only) action.
  final ShortcutCatalogEntry? entry;
}

/// The reference dialog body.
class ShortcutReference extends StatefulWidget {
  const ShortcutReference({
    super.key,
    required this.service,
    required this.i18n,
    required this.onClose,
    this.initialEditing,
  });

  final ShortcutService service;
  final DshI18n Function() i18n;
  final VoidCallback onClose;

  /// Open directly on the editor of this command (tests, deep links).
  final String? initialEditing;

  @override
  State<ShortcutReference> createState() => _ShortcutReferenceState();
}

class _ShortcutReferenceState extends State<ShortcutReference> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _search = FocusNode();
  String? _editing;
  String? _resetRevision;
  bool _busy = false;
  _Toast? _toast;
  int _toastSeq = 0;
  Timer? _toastTimer;
  void Function()? _off;
  void Function()? _offFixed;

  ShortcutService get service => widget.service;
  DshI18n get i18n => widget.i18n();

  @override
  void initState() {
    super.initState();
    _editing = widget.initialEditing;
    _off = service.subscribe(_changed);
    _offFixed = service.subscribeFixed(_changed);
    _query.addListener(_changed);
    if (service.config.status == ShortcutConfigStatus.unreadable) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _notify(
            shortcutReadFailure(service.config, service.runtime, i18n),
            error: true,
          );
        }
      });
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _off?.call();
    _offFixed?.call();
    _toastTimer?.cancel();
    _query.dispose();
    _search.dispose();
    super.dispose();
  }

  String _t(String key, [Map<String, Object?> params = const {}]) =>
      i18n.t('shortcuts', key, params: params);

  void _notify(String text, {bool error = false}) {
    if (!mounted) return;
    _toastTimer?.cancel();
    setState(() => _toast = _Toast(text, error, ++_toastSeq));
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  List<({String id, String label})> get _labels => [
    for (final r in service.catalog) (id: r.id, label: r.label),
    for (final r in service.fixedCatalog) (id: r.id, label: r.label),
  ];

  List<_Row> _rows() {
    final rows = <_Row>[
      for (final r in service.catalog)
        _Row(
          id: r.id,
          label: r.label,
          keys: r.keys,
          group: ShortcutGroup.application,
          entry: r,
          names: [
            ...r.aliases,
            r.keys.where((k) => k != '+').join('+'),
            r.keys.where((k) => k != '+').join(),
            r.aria ?? '',
            r.aria?.replaceAll('Meta', 'Cmd') ?? '',
          ],
        ),
      for (final r in service.fixedCatalog)
        _Row(
          id: r.id,
          label: r.label,
          keys: r.keys,
          group: r.group,
          names: [r.id, r.keys.join(' ')],
        ),
    ];
    int order(_Row r) {
      final i = coreActionOrder.indexOf(r.id);
      return i < 0 ? coreActionOrder.length : i;
    }

    rows.sort((a, b) {
      // Stop stays after the other fixed input actions.
      final stop =
          (a.id == 'response.stop' ? 1 : 0) - (b.id == 'response.stop' ? 1 : 0);
      if (stop != 0) return stop;
      final o = order(a) - order(b);
      return o != 0 ? o : a.id.compareTo(b.id);
    });
    return rows;
  }

  List<_Row> _matches(List<_Row> rows) {
    final q = _query.text.trim();
    if (q.isEmpty) return rows;
    final candidates = [
      for (final row in rows)
        for (final name in row.names) (name: name, label: row.label, row: row),
    ];
    final ranked = rankByName<({String name, String label, _Row row})>(
      candidates,
      q,
      name: (c) => c.name,
      label: (c) => c.label,
    );
    final seen = <_Row>{};
    return [
      for (final c in ranked)
        if (seen.add(c.row)) c.row,
    ];
  }

  Future<ShortcutSaveResult> _persist(
    ShortcutEdit edit,
    String revision,
  ) async {
    setState(() => _busy = true);
    final result = await service.edit(edit, revision);
    if (mounted) setState(() => _busy = false);
    return result;
  }

  Future<void> _resetAll() async {
    final revision = _resetRevision;
    if (revision == null) return;
    final result = await _persist(const ResetAllShortcuts(), revision);
    if (!mounted) return;
    if (result.status == ShortcutSaveStatus.saved ||
        result.status == ShortcutSaveStatus.stale) {
      setState(() => _resetRevision = null);
    }
    _notify(
      result.status == ShortcutSaveStatus.saved
          ? _t('reset-saved')
          : result.status == ShortcutSaveStatus.writeFailed
          ? _t('reset-failed')
          : shortcutFailure(result, _labels, i18n, service.runtime),
      error: result.status != ShortcutSaveStatus.saved,
    );
  }

  void _closeEditor() {
    setState(() => _editing = null);
    _search.requestFocus();
  }

  void _close() {
    if (_busy) return;
    if (_resetRevision != null) {
      setState(() => _resetRevision = null);
    } else if (_editing != null) {
      _closeEditor();
    } else {
      widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final size = MediaQuery.sizeOf(context);
    final rows = _rows();
    final matches = _matches(rows);
    final config = service.config;
    final profile = '${service.runtime.name}:${service.platform.name}';
    final modified = config.document.profiles[profile]?.length ?? 0;
    final width = (size.width).clamp(0.0, 480.0);
    final height = (size.height - 108).clamp(0.0, 600.0);
    final hairline = dshHairlineOf(context);
    final groups = <ShortcutGroup>[
      ShortcutGroup.application,
      ShortcutGroup.input,
      ShortcutGroup.menus,
      ShortcutGroup.approval,
    ];
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            _editing == null &&
            !(HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed)) {
          _close();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, 30),
          child: DshDecoratedBox(
            key: const ValueKey('shortcut-reference'),
            decoration: BoxDecoration(
              color: theme.color('--dsw-alias-bg-layer-2'),
              borderRadius: BorderRadius.circular(24),
              boxShadow: theme.boxShadow('--dsw-elevation-prominent'),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                width: width,
                height: height,
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 46,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 22, 14, 0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: DshChromeText(
                                    _t('title'),
                                    style: theme
                                        .textStyle('--dsw-font-base-strong-16')
                                        .copyWith(color: theme.labelPrimary),
                                  ),
                                ),
                                _IconTap(
                                  key: const ValueKey(
                                    'shortcut-reference-close',
                                  ),
                                  label: _t('close'),
                                  enabled: !_busy,
                                  onTap: _close,
                                  child: DshIcon(
                                    DshIcons.close,
                                    size: 14,
                                    color: theme.labelPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 60,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                            child: _SearchField(
                              controller: _query,
                              focusNode: _search,
                              placeholder: _t('search'),
                              clearLabel: _t('clear-search'),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            key: const ValueKey('shortcut-reference-list'),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                            children: [
                              for (final group in groups)
                                if (matches.any((r) => r.group == group)) ...[
                                  if (group != ShortcutGroup.application)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        8,
                                        18,
                                        8,
                                        4,
                                      ),
                                      child: DshChromeText(
                                        _t(group.name),
                                        style: theme
                                            .textStyle('--dsw-font-xxs-12')
                                            .copyWith(
                                              color: theme.color(
                                                '--dsw-alias-label-tertiary',
                                              ),
                                            ),
                                      ),
                                    ),
                                  for (final row in matches.where(
                                    (r) => r.group == group,
                                  ))
                                    _ReferenceRow(
                                      key: ValueKey('shortcut-row-${row.id}'),
                                      row: row,
                                      editing: _editing == row.id,
                                      busy: _busy,
                                      editable:
                                          config.status ==
                                          ShortcutConfigStatus.ready,
                                      service: service,
                                      i18n: i18n,
                                      labels: _labels,
                                      persist: _persist,
                                      onEdit: () =>
                                          setState(() => _editing = row.id),
                                      onClose: _closeEditor,
                                      onSaved: () {
                                        _notify(_t('saved'));
                                        _closeEditor();
                                      },
                                      onError: (m) => _notify(m, error: true),
                                    ),
                                ],
                              if (matches.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: DshChromeText(
                                      _t('empty'),
                                      style: theme
                                          .textStyle('--dsw-font-xxs-12')
                                          .copyWith(
                                            color: theme.color(
                                              '--dsw-alias-label-tertiary',
                                            ),
                                          ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        DshDecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: theme.color('--dsw-alias-border-l2'),
                                width: hairline,
                              ),
                            ),
                          ),
                          child: SizedBox(
                            height: 52,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: Row(
                                children: [
                                  _ResetAll(
                                    key: const ValueKey('shortcut-reset-all'),
                                    label: _t('reset-all'),
                                    enabled:
                                        !_busy &&
                                        config.status ==
                                            ShortcutConfigStatus.ready &&
                                        modified > 0,
                                    onTap: () => setState(() {
                                      _editing = null;
                                      _resetRevision = config.revision;
                                    }),
                                  ),
                                  const Spacer(),
                                  if (modified > 0)
                                    DshChromeText(
                                      _t('modified-count', {'count': modified}),
                                      key: const ValueKey(
                                        'shortcut-modified-count',
                                      ),
                                      style: theme
                                          .textStyle('--dsw-font-xxs-12')
                                          .copyWith(
                                            color: theme.color(
                                              '--dsw-alias-label-tertiary',
                                            ),
                                          ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_resetRevision != null)
                      _ConfirmReset(
                        key: const ValueKey('shortcut-reset-confirm'),
                        title: _t('reset-title'),
                        description: _t('reset-description'),
                        cancel: _t('cancel'),
                        confirm: _t('reset'),
                        busy: _busy,
                        ready: config.status == ShortcutConfigStatus.ready,
                        onCancel: () => setState(() => _resetRevision = null),
                        onConfirm: _resetAll,
                      ),
                    if (_toast != null)
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: 64,
                        child: _ToastView(
                          key: ValueKey('shortcut-toast-${_toast!.seq}'),
                          toast: _toast!,
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
  }
}

class _Toast {
  const _Toast(this.text, this.error, this.seq);

  final String text;
  final bool error;
  final int seq;
}

class _ToastView extends StatelessWidget {
  const _ToastView({super.key, required this.toast});

  final _Toast toast;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Center(
      child: Semantics(
        liveRegion: true,
        child: DshContainer(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.color('--dsw-alias-tooltip-bg'),
            borderRadius: BorderRadius.circular(theme.radiusMd),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DshIcon(
                toast.error
                    ? DshShellIcons.shortcutError
                    : DshShellIcons.shortcutSuccess,
                size: 16,
                color: toast.error
                    ? theme.color('--dsw-alias-state-warn-secondary')
                    : theme.color('--dsw-alias-state-success-secondary'),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: DshChromeText(
                  toast.text,
                  style: theme
                      .textStyle('--dsw-font-xs-13')
                      .copyWith(
                        color: theme.color('--dsw-static-neutral-bluish-00'),
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconTap extends StatefulWidget {
  const _IconTap({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;
  final bool enabled;

  @override
  State<_IconTap> createState() => _IconTapState();
}

class _IconTapState extends State<_IconTap> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        enabled: widget.enabled,
        label: widget.label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onTap : null,
          child: Opacity(
            opacity: widget.enabled ? 1 : 0.45,
            child: DshContainer(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _hover && widget.enabled
                    ? theme.interactiveBgHover
                    : null,
                borderRadius: BorderRadius.circular(28),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    required this.clearLabel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String placeholder;
  final String clearLabel;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final hairline = dshHairlineOf(context);
    final style = theme
        .textStyle('--dsw-font-xs-13')
        .copyWith(color: theme.labelPrimary, height: 18 / 13);
    return DshContainer(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: theme.color('--dsw-alias-markdown-code-block'),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.color('--dsw-alias-border-l2'),
          width: hairline,
        ),
      ),
      child: Row(
        children: [
          DshIcon(
            DshShellIcons.searchRegular,
            size: 14,
            color: theme.color('--dsw-alias-label-caption'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: EditableText(
              key: const ValueKey('shortcut-search'),
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              style: style,
              cursorColor: theme.labelPrimary,
              backgroundCursorColor: theme.labelSecondary,
              selectionColor: theme.color('--dsw-alias-interactive-bg-active'),
              maxLines: 1,
            ),
          ),
          if (controller.text.isNotEmpty)
            _IconTap(
              key: const ValueKey('shortcut-search-clear'),
              label: clearLabel,
              onTap: () {
                controller.clear();
                focusNode.requestFocus();
              },
              child: DshIcon(
                DshIcons.close,
                size: 10,
                color: theme.labelSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

class _ReferenceRow extends StatefulWidget {
  const _ReferenceRow({
    super.key,
    required this.row,
    required this.editing,
    required this.busy,
    required this.editable,
    required this.service,
    required this.i18n,
    required this.labels,
    required this.persist,
    required this.onEdit,
    required this.onClose,
    required this.onSaved,
    required this.onError,
  });

  final _Row row;
  final bool editing;
  final bool busy;
  final bool editable;
  final ShortcutService service;
  final DshI18n i18n;
  final List<({String id, String label})> labels;
  final Future<ShortcutSaveResult> Function(ShortcutEdit, String) persist;
  final VoidCallback onEdit;
  final VoidCallback onClose;
  final VoidCallback onSaved;
  final void Function(String message) onError;

  @override
  State<_ReferenceRow> createState() => _ReferenceRowState();
}

class _ReferenceRowState extends State<_ReferenceRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final row = widget.row;
    final entry = row.entry;
    final canEdit =
        entry != null && widget.editable && !widget.busy && !widget.editing;
    Widget binding;
    if (entry == null) {
      binding = _Keys(keys: row.keys, fixed: true);
    } else if (widget.editing) {
      binding = _ShortcutEditor(
        key: ValueKey('shortcut-editor-${row.id}'),
        target: entry,
        service: widget.service,
        i18n: widget.i18n,
        labels: widget.labels,
        persist: widget.persist,
        onClose: widget.onClose,
        onSaved: widget.onSaved,
        onError: widget.onError,
      );
    } else {
      binding = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: _hover ? 1 : 0,
            child: SizedBox(
              width: 20,
              height: 26,
              child: Center(
                child: DshIcon(
                  DshShellIcons.shortcutEdit,
                  size: 12,
                  color: theme.color('--dsw-alias-label-tertiary'),
                ),
              ),
            ),
          ),
          row.keys.isEmpty
              ? _Pill(text: widget.i18n.t('shortcuts', 'unbound'), muted: true)
              : _Keys(keys: row.keys, fixed: false),
        ],
      );
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: canEdit ? SystemMouseCursors.click : MouseCursor.defer,
      child: Semantics(
        button: entry != null,
        enabled: canEdit,
        label: entry == null
            ? row.label
            : widget.i18n.t(
                'shortcuts',
                'edit-label',
                params: {'command': row.label},
              ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canEdit ? widget.onEdit : null,
          child: DshContainer(
            constraints: const BoxConstraints(minHeight: 42),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _hover && canEdit ? theme.interactiveBgHover : null,
              borderRadius: BorderRadius.circular(theme.radiusMd),
            ),
            child: Row(
              children: [
                Expanded(
                  child: DshChromeText(
                    row.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme
                        .textStyle('--dsw-font-xs-13')
                        .copyWith(color: theme.labelPrimary, height: 18 / 13),
                  ),
                ),
                const SizedBox(width: 8),
                binding,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Keys extends StatelessWidget {
  const _Keys({required this.keys, required this.fixed});

  final List<String> keys;
  final bool fixed;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return DshContainer(
      height: 26,
      padding: EdgeInsets.symmetric(horizontal: fixed ? 0 : 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fixed ? null : theme.color('--dsw-alias-bg-module-platform'),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DshShortcutKeys(
        keys: keys,
        color: fixed
            ? theme.color('--dsw-alias-label-tertiary')
            : theme.labelSecondary,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return DshContainer(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.color('--dsw-alias-bg-module-platform'),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DshChromeText(
        text,
        maxLines: 1,
        style: theme
            .textStyle('--dsw-font-xxs-12')
            .copyWith(
              color: muted
                  ? theme.color('--dsw-alias-label-tertiary')
                  : theme.labelSecondary,
              height: 14 / 12,
            ),
      ),
    );
  }
}

class _ResetAll extends StatelessWidget {
  const _ResetAll({
    super.key,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Semantics(
          button: true,
          enabled: enabled,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  DshIcon(
                    DshIcons.refresh,
                    size: 12,
                    color: theme.labelSecondary,
                  ),
                  const SizedBox(width: 8),
                  DshChromeText(
                    label,
                    style: theme
                        .textStyle('--dsw-font-xxs-12')
                        .copyWith(color: theme.labelSecondary),
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

class _ConfirmReset extends StatelessWidget {
  const _ConfirmReset({
    super.key,
    required this.title,
    required this.description,
    required this.cancel,
    required this.confirm,
    required this.busy,
    required this.ready,
    required this.onCancel,
    required this.onConfirm,
  });

  final String title;
  final String description;
  final String cancel;
  final String confirm;
  final bool busy;
  final bool ready;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Positioned.fill(
      child: ColoredBox(
        color: theme.color('--dsw-alias-bg-mask-1'),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: DshContainer(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.color('--dsw-alias-bg-layer-2'),
                borderRadius: BorderRadius.circular(theme.radiusLg),
                boxShadow: theme.boxShadow('--dsw-elevation-prominent'),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DshChromeText(
                    title,
                    style: theme
                        .textStyle('--dsw-font-base-strong-16')
                        .copyWith(color: theme.labelPrimary),
                  ),
                  const SizedBox(height: 8),
                  DshChromeText(
                    description,
                    style: theme
                        .textStyle('--dsw-font-s-14')
                        .copyWith(color: theme.labelSecondary),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      DshButton(
                        key: const ValueKey('shortcut-reset-cancel'),
                        variant: DshButtonVariant.outline,
                        onPressed: busy ? null : onCancel,
                        child: DshChromeText(cancel),
                      ),
                      const SizedBox(width: 8),
                      DshButton(
                        key: const ValueKey('shortcut-reset-confirm-button'),
                        variant: DshButtonVariant.primary,
                        onPressed: busy || !ready ? null : onConfirm,
                        child: DshChromeText(confirm),
                      ),
                    ],
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

/// Inline physical-key recording and revision-aware command editing (dsh
/// `Editor.tsx`): Reset, Remove and the recorder. A released combination is
/// saved against the configuration the user reviewed; a failure keeps the draft
/// and offers another recording.
class _ShortcutEditor extends StatefulWidget {
  const _ShortcutEditor({
    super.key,
    required this.target,
    required this.service,
    required this.i18n,
    required this.labels,
    required this.persist,
    required this.onClose,
    required this.onSaved,
    required this.onError,
  });

  final ShortcutCatalogEntry target;
  final ShortcutService service;
  final DshI18n i18n;
  final List<({String id, String label})> labels;
  final Future<ShortcutSaveResult> Function(ShortcutEdit, String) persist;
  final VoidCallback onClose;
  final VoidCallback onSaved;
  final void Function(String message) onError;

  @override
  State<_ShortcutEditor> createState() => _ShortcutEditorState();
}

class _ShortcutEditorState extends State<_ShortcutEditor> {
  final FocusNode _recorder = FocusNode(debugLabel: 'shortcut-recorder');
  late String _revision;
  ShortcutBinding? _candidate;
  bool _captured = false;
  bool _busy = false;
  bool _writing = false;
  String _message = '';
  ShortcutBinding? _retry;
  void Function()? _off;
  void Function()? _modal;

  // Recording state (dsh keeps these in the effect's closure).
  ShortcutBinding? _pending;
  bool _blocked = false;
  final Set<String> _held = {};

  ShortcutService get service => widget.service;
  bool get _chords =>
      service.runtime == ShortcutRuntime.desktop &&
      (service.platform == ShortcutPlatform.macos ||
          service.platform == ShortcutPlatform.windows);

  String _t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t('shortcuts', key, params: params);

  @override
  void initState() {
    super.initState();
    _revision = service.config.revision;
    _off = service.subscribe(() {
      if (mounted) setState(() {});
    });
    // The recorder owns the keyboard: no command runs while it records.
    _modal = service.modals.push('shortcut-edit');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recorder.requestFocus();
    });
  }

  @override
  void dispose() {
    _off?.call();
    _modal?.call();
    _recorder.dispose();
    super.dispose();
  }

  bool get _stale => _revision != service.config.revision;

  void _report(String text) {
    setState(() => _message = text);
    widget.onError(text);
  }

  Future<void> _save(ShortcutEdit edit, [String? reviewed]) async {
    if (_writing) return;
    _writing = true;
    setState(() => _busy = true);
    final result = await widget.persist(edit, reviewed ?? _revision);
    if (!mounted) return;
    _writing = false;
    setState(() => _busy = false);
    if (result.status == ShortcutSaveStatus.saved) {
      widget.onSaved();
    } else {
      setState(() => _retry = edit is SetShortcut ? edit.binding : null);
      _report(
        shortcutFailure(result, widget.labels, widget.i18n, service.runtime),
      );
    }
  }

  void _capture(ShortcutBinding binding) {
    final id = widget.target.id;
    setState(() {
      _candidate = binding;
      _captured = true;
      _retry = null;
    });
    final described = service.describeBinding(binding);
    final conflicts = [
      for (final c in described.conflicts)
        if (c != id)
          widget.labels
                  .where((r) => r.id == c)
                  .map((r) => r.label)
                  .firstOrNull ??
              c,
    ];
    if (described.issue != null) {
      _report(_t(described.issue!.key));
      return;
    }
    if (conflicts.isNotEmpty) {
      _report(_t('conflict', {'commands': conflicts.join(', ')}));
      return;
    }
    if (_stale) {
      setState(() => _retry = binding);
      _report(_t('stale'));
      return;
    }
    final config = service.config;
    if (config.status != ShortcutConfigStatus.ready) {
      _report(
        config.status == ShortcutConfigStatus.loading
            ? _t('not-ready')
            : shortcutReadFailure(config, service.runtime, widget.i18n),
      );
      return;
    }
    unawaited(_save(SetShortcut(id, binding)));
  }

  void _resetRecording() {
    _pending = null;
    _held.clear();
    _blocked = false;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final kb = HardwareKeyboard.instance;
    final code = domCodeOf(event.physicalKey);
    final modifiers = [
      if (kb.isControlPressed) ShortcutModifier.control,
      if (kb.isAltPressed) ShortcutModifier.alt,
      if (kb.isShiftPressed) ShortcutModifier.shift,
      if (kb.isMetaPressed) ShortcutModifier.meta,
    ];
    if (event is KeyUpEvent) {
      if (code == null) return KeyEventResult.handled;
      _held.remove(code);
      final pending = _pending;
      final isModifier = isModifierCode(code);
      final modifierName = isModifier
          ? code.replaceAll(RegExp(r'(Left|Right)$'), '').toLowerCase()
          : null;
      final binding =
          pending != null &&
              (pending.code == code ||
                  pending.secondCode == code ||
                  pending.modifiers.any((m) => m.name == modifierName))
          ? pending
          : null;
      if (binding != null) {
        _pending = null;
        _blocked = _chords;
      }
      // macOS can omit the character keyup while Command is held.
      if (_chords &&
          (_held.isEmpty ||
              (service.platform == ShortcutPlatform.macos &&
                  code.startsWith('Meta')))) {
        _held.clear();
        _blocked = false;
      }
      if (binding != null) _capture(binding);
      return KeyEventResult.handled;
    }
    if (code == null) {
      return KeyEventResult.handled;
    }
    if (code == 'Escape' && modifiers.isEmpty && !_chords) {
      if (event is KeyDownEvent && !_writing) widget.onClose();
      return KeyEventResult.handled;
    }
    if (_writing || event is KeyRepeatEvent) return KeyEventResult.handled;
    if (isModifierCode(code)) {
      if (_chords && _pending != null) {
        _resetRecording();
        setState(() {
          _candidate = null;
          _captured = false;
        });
      }
      return KeyEventResult.handled;
    }
    if (_chords) {
      _held.add(code);
      if (_blocked) return KeyEventResult.handled;
      if (_held.length > 2) {
        _blocked = true;
        _pending = null;
        _report(_t('too-many-keys'));
        return KeyEventResult.handled;
      }
    }
    try {
      final codes = [code, if (_chords) ..._held.where((c) => c != code)];
      final binding = ShortcutBinding(
        codes[0],
        modifiers,
        codes.length > 1 ? codes[1] : null,
      );
      _pending = service.describeBinding(binding).binding?.toBinding();
      setState(() {
        _candidate = _pending;
        _captured = _chords;
        _message = '';
        _retry = null;
      });
    } on ShortcutBindingError {
      _blocked = _chords;
      _pending = null;
      _report(_t('unsupported-key'));
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final config = service.config;
    final readonly =
        _busy || _stale || config.status != ShortcutConfigStatus.ready;
    final hairline = dshHairlineOf(context);
    final help = _message.isNotEmpty
        ? _message
        : _chords
        ? ''
        : _t(
            service.runtime == ShortcutRuntime.web
                ? (service.platform == ShortcutPlatform.windows
                      ? 'windows-web-help'
                      : service.platform == ShortcutPlatform.macos
                      ? 'macos-web-help'
                      : 'web-help')
                : 'record-help',
          );
    Widget action(String label, VoidCallback? onTap, {Key? key}) => Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: MouseRegion(
        cursor: onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: Semantics(
          button: true,
          enabled: onTap != null,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: DshChromeText(
              label,
              style: theme
                  .textStyle('--dsw-font-xxs-12')
                  .copyWith(color: theme.color('--dsw-alias-label-tertiary')),
            ),
          ),
        ),
      ),
    );
    final described = _captured && _message.isEmpty && _candidate != null
        ? service.describeBinding(_candidate).keys
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            action(
              _t('reset'),
              readonly
                  ? null
                  : () => unawaited(_save(ResetShortcut(widget.target.id))),
              key: const ValueKey('shortcut-reset'),
            ),
            const SizedBox(width: 8),
            if (widget.target.binding != null) ...[
              action(
                _t('clear'),
                readonly
                    ? null
                    : () =>
                          unawaited(_save(SetShortcut(widget.target.id, null))),
                key: const ValueKey('shortcut-clear'),
              ),
              const SizedBox(width: 8),
            ],
            Focus(
              focusNode: _recorder,
              onKeyEvent: _onKey,
              onFocusChange: (focused) {
                if (!focused) _resetRecording();
              },
              child: Semantics(
                button: true,
                label: _t('record'),
                child: GestureDetector(
                  key: const ValueKey('shortcut-recorder'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_writing) return;
                    _recorder.requestFocus();
                    _resetRecording();
                    setState(() {
                      _captured = false;
                      _message = '';
                      _retry = null;
                    });
                  },
                  child: DshContainer(
                    constraints: const BoxConstraints(minWidth: 96),
                    height: 26,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 3,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.color('--dsw-alias-bg-module-platform'),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _message.isNotEmpty
                            ? theme.color('--dsw-alias-state-error-primary')
                            : theme.color('--dsw-alias-border-l4'),
                        width: _message.isNotEmpty ? 1 : hairline,
                      ),
                    ),
                    child: described != null
                        ? DshShortcutKeys(
                            keys: described,
                            color: theme.labelSecondary,
                          )
                        : DshChromeText(
                            _t('record'),
                            style: theme
                                .textStyle('--dsw-font-xxs-12')
                                .copyWith(color: theme.labelSecondary),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (help.isNotEmpty && _message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Semantics(
              liveRegion: true,
              child: DshChromeText(
                help,
                key: const ValueKey('shortcut-message'),
                textAlign: TextAlign.end,
                style: theme
                    .textStyle('--dsw-font-xxs-12')
                    .copyWith(
                      color: theme.color('--dsw-alias-state-error-primary'),
                    ),
              ),
            ),
          ),
        if (_stale)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                DshChromeText(
                  _t('stale'),
                  style: theme
                      .textStyle('--dsw-font-xxs-12')
                      .copyWith(
                        color: theme.color('--dsw-alias-label-tertiary'),
                      ),
                ),
                action(
                  _t('review'),
                  _busy
                      ? null
                      : () => setState(() {
                          _revision = service.config.revision;
                          _message = '';
                        }),
                  key: const ValueKey('shortcut-review'),
                ),
              ],
            ),
          ),
        if (_retry != null && !_stale)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: action(
              _t('retry-save'),
              readonly ? null : () => _capture(_retry!),
              key: const ValueKey('shortcut-retry'),
            ),
          ),
      ],
    );
  }
}
