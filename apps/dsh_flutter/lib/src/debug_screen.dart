import 'package:dsh_feature_approval/dsh_feature_approval.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';

import 'debug_controller.dart';

/// Phase-0 debug screen: host URL + token -> pair -> list sessions -> open one
/// -> send a prompt -> streamed assistant text -> approval takeover.
/// Deliberately plain; the product UI is phase 1.
class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key, required this.controller});

  final DebugController controller;

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  final _url = TextEditingController(text: 'http://127.0.0.1:3080');
  final _token = TextEditingController();
  final _cwd = TextEditingController();
  final _prompt = TextEditingController();

  DebugController get c => widget.controller;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    _cwd.dispose();
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<DshThemeData>()!;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Scaffold(
        backgroundColor: theme.color('--dsw-alias-bg-layer-1'),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: DefaultTextStyle(
              style: theme
                  .textStyle('--dsw-font-s-14')
                  .copyWith(color: theme.color('--dsw-alias-label-primary')),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _connectRow(theme),
                  const SizedBox(height: 8),
                  Text(
                    'status: ${c.status}${c.error == null ? '' : '   error: ${c.error}'}',
                    key: const ValueKey('status'),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 280, child: _sessionList(theme)),
                        const SizedBox(width: 12),
                        Expanded(child: _conversation(theme)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctl, {
    bool obscure = false,
    double? width,
    Key? key,
  }) => SizedBox(
    width: width,
    child: TextField(
      key: key,
      controller: ctl,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Widget _connectRow(DshThemeData theme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _field('Host URL', _url, width: 280, key: const ValueKey('url')),
        _field(
          'Launch token',
          _token,
          obscure: true,
          width: 240,
          key: const ValueKey('token'),
        ),
        DshButton(
          key: const ValueKey('connect'),
          variant: DshButtonVariant.primary,
          onPressed: () => c.connect(_url.text, _token.text),
          child: const Text('Pair'),
        ),
        DshButton(
          key: const ValueKey('locale'),
          variant: DshButtonVariant.outline,
          onPressed: () => c.setLocale(
            c.locale == DshLocale.en ? DshLocale.zh : DshLocale.en,
          ),
          child: Text(c.locale == DshLocale.en ? 'EN' : '中文'),
        ),
        DshButton(
          key: const ValueKey('theme'),
          variant: DshButtonVariant.outline,
          onPressed: () => c.setThemePreference(
            ThemePreference.values[(c.themePreference.index + 1) %
                ThemePreference.values.length],
          ),
          child: Text('theme: ${c.themePreference.name}'),
        ),
      ],
    );
  }

  Widget _sessionList(DshThemeData theme) {
    final m = c.manager;
    final items = m?.list.value.items ?? const <SessionListEntry>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _field('Scratch cwd', _cwd, key: const ValueKey('cwd')),
            ),
            const SizedBox(width: 8),
            DshButton(
              key: const ValueKey('create'),
              size: DshButtonSize.sm,
              variant: DshButtonVariant.outline,
              onPressed: m == null ? null : () => c.createSession(_cwd.text),
              child: const Text('New'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('${items.length} sessions', key: const ValueKey('count')),
        Expanded(
          child: ListView(
            children: [
              for (final item in items)
                InkWell(
                  key: ValueKey('session-${item.sessionId}'),
                  onTap: () => c.openSession(item.sessionId),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 8,
                          color: item.summary.running
                              ? theme.color('--dsw-alias-state-warn-primary')
                              : theme.color('--dsw-alias-border-l4'),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.title ?? item.sessionId,
                            overflow: TextOverflow.ellipsis,
                            style: item.sessionId == c.session?.sessionId
                                ? const TextStyle(fontWeight: FontWeight.w600)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _conversation(DshThemeData theme) {
    final s = c.session;
    if (s == null) {
      return const Center(child: Text('Select or create a session'));
    }
    final snap = s.snapshot.value;
    final nodes = c.chat.nodes;
    final approval = c.slots.renderChain(
      composerSlot,
      ComposerOwner(s.sessionId),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${snap.openState.name}${snap.running ? ' · running' : ''}${snap.hasMore ? ' · older history available' : ''}',
          key: const ValueKey('session-state'),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            key: const ValueKey('transcript'),
            children: [
              for (final n in nodes)
                Container(
                  key: ValueKey('node-${n.id}'),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.color(
                      n.key == 'user'
                          ? '--dsw-alias-bg-layer-3'
                          : '--dsw-alias-bg-layer-2',
                    ),
                    borderRadius: BorderRadius.circular(
                      theme.number('--dsw-radius-md'),
                    ),
                  ),
                  child: Text(
                    '${n.key == 'user' ? 'You' : 'Assistant'}${n.streaming ? ' (streaming)' : ''}: ${n.data['text']}',
                  ),
                ),
            ],
          ),
        ),
        if (approval != null) approval else _composer(),
      ],
    );
  }

  Widget _composer() => Row(
    children: [
      Expanded(child: _field('Prompt', _prompt, key: const ValueKey('prompt'))),
      const SizedBox(width: 8),
      DshButton(
        key: const ValueKey('send'),
        variant: DshButtonVariant.primary,
        onPressed: () {
          final text = _prompt.text;
          _prompt.clear();
          c.send(text);
        },
        child: const Text('Send'),
      ),
      const SizedBox(width: 8),
      DshButton(
        key: const ValueKey('cancel'),
        variant: DshButtonVariant.outline,
        onPressed: c.session?.snapshot.value.running == true ? c.cancel : null,
        child: const Text('Cancel'),
      ),
    ],
  );
}
