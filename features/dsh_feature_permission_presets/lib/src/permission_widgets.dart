import 'package:dsh_client/generated_commands.dart' as cmd;
import 'package:dsh_client/generated_permission_presets.dart' as perm;
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'permission_catalog.dart';
import 'permission_default.dart';
import 'presentation.dart';

DshIconData? _glyph(String value) => switch (value) {
  'read-only' => DshIcons.permissionReadOnly,
  'workspace-write' => DshIcons.permissionWorkspaceWrite,
  fullAccessPreset => DshIcons.permissionFullAccess,
  autoReviewPreset => DshIcons.permissionAutoReview,
  _ => null,
};

/// The Settings row for the default permission of new sessions (dsh
/// `PermissionRow`): the preset selector pill over the host's
/// `defaultPreset`. Full access asks for the risk acknowledgement first. The
/// value only applies to sessions created later; the current session is
/// switched from the composer control.
class PermissionRow extends StatefulWidget {
  const PermissionRow({
    super.key,
    required this.controller,
    required this.i18n,
  });

  final PermissionDefaults controller;
  final DshI18n i18n;

  @override
  State<PermissionRow> createState() => _PermissionRowState();
}

class _PermissionRowState extends State<PermissionRow> {
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  String _t(String key) => widget.i18n.t(settingsPermissionNs, key);

  String _label(PermissionDefaultOption o) =>
      displayPermissionPreset(o.id, o.label, widget.i18n);

  Future<void> _open(PermissionSettingsState state) async {
    final id = await showDshOptionSheet(
      context,
      selectedId: state.currentValue,
      options: [
        for (final o in state.options) DshOption(id: o.id, label: _label(o)),
      ],
    );
    if (id == null || id == state.currentValue || !mounted) return;
    if (id == fullAccessPreset) {
      setState(() => _confirming = true);
      final confirmed = await showDshRiskDialog(
        context,
        title: _t('confirm.title'),
        description: _t('confirm.description'),
        acknowledgeLabel: _t('confirm.acknowledge'),
        cancelLabel: _t('confirm.cancel'),
        closeLabel: _t('close'),
        confirmLabel: _t('confirm.enable'),
      );
      if (mounted) setState(() => _confirming = false);
      if (!confirmed) return;
    }
    await widget.controller.select(id);
  }

  @override
  Widget build(BuildContext context) {
    return DshWatch(
      changes: widget.controller.state.changes,
      builder: (context) {
        final state = widget.controller.state.value;
        if (state.status == PermissionRowStatus.unavailable) {
          return const SizedBox.shrink();
        }
        PermissionDefaultOption? selected;
        for (final o in state.options) {
          if (o.id == state.currentValue) selected = o;
        }
        final busy =
            state.status == PermissionRowStatus.loading ||
            state.status == PermissionRowStatus.saving ||
            _confirming;
        final label = selected != null
            ? _label(selected)
            : (busy ? _t('loading') : _t('unavailable'));
        return DshSettingsRow(
          key: const ValueKey('permission-row'),
          title: _t('title'),
          description: state.error ?? _t('description'),
          alert: state.error != null,
          control: KeyedSubtree(
            key: const ValueKey<String>('permission-selector'),
            child: DshSelectorPill(
              label: label,
              onPressed: busy || !state.writable || state.options.isEmpty
                  ? null
                  : () => _open(state),
            ),
          ),
        );
      },
    );
  }
}

/// The current session's permission control (dsh `PermissionSelect`, slot
/// `conversation.input.permission`): a chip with the mode's glyph and name
/// opening the preset choices. A pick submits the `/permission <preset>`
/// command line; the pushed `permissions` projection frame is the one
/// confirmation. Full access and Auto review each ask for their own risk
/// acknowledgement first.
class PermissionSelect extends StatefulWidget {
  const PermissionSelect({
    super.key,
    required this.owner,
    required this.catalog,
    required this.submit,
    required this.i18n,
  });

  final SessionOwner owner;
  final PermissionCatalogDirectory catalog;

  /// Submit one preset for [owner]'s session; completes when the host
  /// accepted the command and throws when it did not.
  final Future<void> Function(String sessionId, String preset) submit;
  final DshI18n i18n;

  @override
  State<PermissionSelect> createState() => _PermissionSelectState();
}

class _PermissionSelectState extends State<PermissionSelect> {
  String? _pick;
  bool _confirming = false;

  String _t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t(permissionAccessNs, key, params: params);

  String _name(perm.PresetOption o) => o.value == autoReviewPreset
      ? _t('auto.label')
      : displayPermissionPreset(
          o.value,
          o.name,
          widget.i18n,
          namespace: permissionAccessNs,
        );

  Future<void> _submit(String id) async {
    setState(() => _pick = id);
    try {
      await widget.submit(widget.owner.sessionId, id);
    } on Object {
      // dsh swallows the failure too: the chip returns to the projection's
      // value, which is the host's answer.
    } finally {
      if (mounted) setState(() => _pick = null);
    }
  }

  Future<void> _open(perm.PermissionCatalog catalog, String current) async {
    final id = await showDshOptionSheet(
      context,
      selectedId: current,
      options: [
        for (final o in catalog.options)
          DshOption(
            id: o.value,
            label: _name(o),
            icon: _glyph(o.value),
            badge: o.value == autoReviewPreset ? _t('auto.badge') : null,
            detail: o.value == autoReviewPreset
                ? _t('auto.description')
                : o.description,
          ),
      ],
    );
    if (id == null || id == current || !mounted) return;
    if (id == fullAccessPreset || id == autoReviewPreset) {
      final auto = id == autoReviewPreset;
      setState(() => _confirming = true);
      final confirmed = await showDshRiskDialog(
        context,
        title: _t(auto ? 'auto.confirm.title' : 'confirm.title'),
        description: _t(
          auto ? 'auto.confirm.description' : 'confirm.description',
        ),
        acknowledgeLabel: _t(
          auto ? 'auto.confirm.acknowledge' : 'confirm.acknowledge',
        ),
        cancelLabel: _t('confirm.cancel'),
        closeLabel: _t('close'),
        confirmLabel: _t(auto ? 'auto.confirm.enable' : 'confirm.enable'),
      );
      if (mounted) setState(() => _confirming = false);
      if (!confirmed) return;
    }
    await _submit(id);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.owner.session;
    return DshWatch(
      changes: widget.catalog.value.changes,
      builder: (context) => DshWatch(
        changes: session.projections.changes,
        builder: (context) {
          final selection = session.projections.get('permissions');
          final catalog = widget.catalog.value.value;
          final stored = selection is Map ? selection['currentValue'] : null;
          // No `permissions` projection: the host composes no permission
          // service; no catalog yet: nothing to choose from. Either hides it.
          if (stored is! String || catalog == null) {
            return const SizedBox.shrink();
          }
          final current =
              _pick != null && catalog.options.any((o) => o.value == _pick)
              ? _pick!
              : stored;
          perm.PresetOption? option;
          for (final o in catalog.options) {
            if (o.value == current) option = o;
          }
          final label = option == null
              ? displayPermissionPreset(
                  current,
                  current,
                  widget.i18n,
                  namespace: permissionAccessNs,
                )
              : _name(option);
          final busy = _pick != null || _confirming;
          return _Chip(
            glyph: _glyph(current),
            label: label,
            semanticLabel: _t('mode', {'name': label}),
            onPressed: busy ? null : () => _open(catalog, stored),
          );
        },
      ),
    );
  }
}

class _Chip extends StatefulWidget {
  const _Chip({
    required this.glyph,
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
  });

  final DshIconData? glyph;
  final String label;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final enabled = widget.onPressed != null;
    final color = enabled
        ? theme.labelSecondary
        : theme.color('--dsw-alias-label-dimmed');
    final style = theme
        .textStyle('--dsw-font-xs-strong-13')
        .copyWith(color: color, height: 20 / 13);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: const ValueKey('permission-chip'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220, minHeight: 28),
            child: DshContainer(
              height: 28,
              padding: const EdgeInsets.only(left: 8, right: 4),
              decoration: theme.cornerDecoration(
                theme.radiusSm,
                color: _hovered && enabled ? theme.interactiveBgHover : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.glyph != null) ...[
                    DshIcon(widget.glyph!, size: 14, color: color),
                    const SizedBox(width: 4),
                  ],
                  if (widget.glyph == null ||
                      !DshComposerRow.compactOf(context))
                    Flexible(
                      child: DshChromeText(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      ),
                    ),
                  if (widget.glyph == null ||
                      !DshComposerRow.compactOf(context))
                    const SizedBox(width: 4),
                  DshIcon(
                    DshIcons.chevronDown,
                    color: theme.color('--dsw-alias-label-caption'),
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

/// Run `/permission <preset>` for [sessionId] (dsh `submit`): throws unless the
/// host accepted the command.
Future<void> submitPermission(
  HostRemotes remotes,
  String sessionId,
  String preset,
) async {
  final done = await remotes.commands.execute(
    sessionId,
    '/permission $preset',
    const [],
  );
  if (done == null) throw StateError('the host offers no /permission command');
  final result = done.result;
  if (result is cmd.CommandResultError) {
    throw StateError('permission switch failed: ${result.text}');
  }
}
