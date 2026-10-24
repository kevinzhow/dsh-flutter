import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// The terminal's card on the guide page (dsh `TerminalGuide`): the card opens
/// the remembered available shell at once, and the separate arrow beside the
/// title lists the installed shells; picking one remembers it and opens that
/// shell. Listing allocates no process.
class TerminalGuideCard extends StatelessWidget {
  const TerminalGuideCard({
    super.key,
    required this.owner,
    required this.terminals,
    required this.i18n,
  });

  final SidebarGuideOwner owner;
  final ClientTerminals terminals;
  final DshI18n i18n;

  String _t(String key, [Map<String, Object?> params = const {}]) =>
      i18n.t('sidebarTerminal', key, params: params);

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return DshGuideCard(
      icon: const DshTerminalArtwork(size: 26),
      title: _t('new'),
      description: _t('description'),
      semanticLabel: '${_t('new')} ${_t('description')}',
      onTap: () => owner.actions.openTab(owner.kind, replaceTabId: owner.tabId),
      titleTrailing: Semantics(
        button: true,
        label: _t('shell'),
        child: GestureDetector(
          key: const ValueKey('terminal-shell-menu'),
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_chooseShell(context)),
          child: SizedBox(
            width: 28,
            height: 28,
            child: Center(
              child: DshIcon(
                DshIcons.chevronDown,
                size: 14,
                color: theme.color('--dsw-alias-label-tertiary'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseShell(BuildContext context) async {
    final sessionId = owner.session.sessionId;
    final future = terminals.launchShells(sessionId);
    TerminalLaunchShells? shells;
    String? failure;
    try {
      shells = await future;
    } on Object catch (error) {
      failure = error.toString();
    }
    if (!context.mounted) return;
    final options = shells == null
        ? [
            DshOption(
              id: 'error',
              label: _t('failed', {'message': failure}),
              enabled: false,
            ),
            DshOption(id: 'retry', label: _t('retry')),
          ]
        : shells.shells.isEmpty
        ? [DshOption(id: 'empty', label: _t('shellEmpty'), enabled: false)]
        : [
            for (final shell in shells.shells)
              DshOption(id: shell.path, label: shell.name),
          ];
    final picked = await showDshOptionSheet(
      context,
      options: options,
      selectedId: shells?.selectedShell,
      title: _t('shell'),
    );
    if (picked == null) return;
    if (picked == 'retry') {
      if (context.mounted) await _chooseShell(context);
      return;
    }
    terminals.selectShell(picked);
    owner.actions.openTab(
      owner.kind,
      replaceTabId: owner.tabId,
      params: {'shellPath': picked},
    );
  }
}
