import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show Icons, RefreshIndicator;
import 'package:flutter/widgets.dart';

/// Relative time of [then] against [now] in the app copy ("5 min ago").
String relativeTime(DshI18n i18n, DateTime now, DateTime then) {
  String a(String key, [Map<String, Object?> p = const {}]) =>
      i18n.t(appNamespace, key, params: p);
  final d = now.difference(then);
  if (d.inMinutes < 1) return a('time.justNow');
  if (d.inMinutes < 60) return a('time.minutes', {'n': d.inMinutes});
  if (d.inHours < 24) return a('time.hours', {'n': d.inHours});
  return a('time.days', {'n': d.inDays});
}

/// Last path segment of a working directory, for the row subtitle.
String cwdLeaf(String? cwd) {
  if (cwd == null || cwd.isEmpty) return '';
  final parts = cwd.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty);
  return parts.isEmpty ? cwd : parts.last;
}

/// The session list (dsh `ui-session`): one row per session with its title
/// projection, the working directory and activity, a running dot, pull to
/// refresh, and the empty / loading / failed states. Rows carry only host data
/// already in the list baseline; nothing opens a session until it is tapped.
class SessionListView extends StatelessWidget {
  const SessionListView({
    super.key,
    required this.snapshot,
    required this.i18n,
    required this.onOpen,
    required this.onRefresh,
    required this.onNew,
    this.now,
  });

  final SessionListSnapshot snapshot;
  final DshI18n i18n;
  final ValueChanged<String> onOpen;
  final Future<void> Function() onRefresh;
  final VoidCallback onNew;

  /// Clock for the relative times; tests pin it.
  final DateTime? now;

  String _a(String key) => i18n.t(appNamespace, key);

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final items = snapshot.items
        .where((e) => !e.summary.blank || e.summary.running)
        .toList();
    if (snapshot.state == ListState.error && items.isEmpty) {
      return _Message(
        key: const ValueKey('sessions-error'),
        title: _a('sessions.loadFailed'),
        body: '${snapshot.error}',
        action: DshButton(
          variant: DshButtonVariant.primary,
          onPressed: onRefresh,
          child: Text(i18n.t('common', 'retry')),
        ),
      );
    }
    if (items.isEmpty) {
      if (snapshot.state == ListState.loading ||
          snapshot.phase == ListPhase.pending) {
        return Center(
          key: const ValueKey('sessions-loading'),
          child: Text(
            i18n.t('common', 'loading'),
            style: theme
                .textStyle('--dsw-font-s-14')
                .copyWith(color: theme.labelSecondary),
          ),
        );
      }
      return _Message(
        key: const ValueKey('sessions-empty'),
        title: _a('sessions.empty.title'),
        body: _a('sessions.empty.body'),
        action: DshButton(
          key: const ValueKey('sessions-empty-new'),
          variant: DshButtonVariant.primary,
          onPressed: onNew,
          child: Text(_a('sessions.new')),
        ),
      );
    }
    final clock = now ?? DateTime.now();
    final sorted = [...items]
      ..sort((a, b) => b.summary.updatedAt.compareTo(a.summary.updatedAt));
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: DshSpace.readableWidth),
          child: ListView.separated(
            key: const ValueKey('sessions-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(DshSpace.lg),
            itemCount: sorted.length,
            separatorBuilder: (_, _) => const SizedBox(height: DshSpace.sm),
            itemBuilder: (_, i) => _Row(
              entry: sorted[i],
              i18n: i18n,
              now: clock,
              onTap: () => onOpen(sorted[i].sessionId),
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.i18n,
    required this.now,
    required this.onTap,
  });

  final SessionListEntry entry;
  final DshI18n i18n;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final s = entry.summary;
    final title = (entry.title ?? '').trim();
    final status = s.running
        ? DshStatus.running
        : (s.agentAvailable ? DshStatus.idle : DshStatus.error);
    final subtitle = [
      cwdLeaf(s.cwd),
      relativeTime(
        i18n,
        now,
        DateTime.fromMillisecondsSinceEpoch(s.updatedAt.toInt()),
      ),
    ].where((p) => p.isNotEmpty).join(' · ');
    return Semantics(
      button: true,
      label: title.isEmpty ? i18n.t(appNamespace, 'sessions.untitled') : title,
      child: GestureDetector(
        key: ValueKey('session-row-${s.sessionId}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DshCard(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: DshSpace.touch),
            child: Row(
              children: [
                DshStatusDot(status),
                const SizedBox(width: DshSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty
                            ? i18n.t(appNamespace, 'sessions.untitled')
                            : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme
                            .textStyle('--dsw-font-base-strong-16')
                            .copyWith(color: theme.labelPrimary),
                      ),
                      const SizedBox(height: DshSpace.xs),
                      Text(
                        s.running
                            ? '${i18n.t(appNamespace, 'sessions.running')} · $subtitle'
                            : subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme
                            .textStyle('--dsw-font-xxs-12')
                            .copyWith(
                              color: theme.color('--dsw-alias-label-tertiary'),
                            ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: theme.color('--dsw-alias-label-tertiary'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.title,
    required this.body,
    required this.action,
  });

  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DshSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme
                  .textStyle('--dsw-font-base-strong-16')
                  .copyWith(color: theme.labelPrimary),
            ),
            const SizedBox(height: DshSpace.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme
                  .textStyle('--dsw-font-s-14')
                  .copyWith(color: theme.labelSecondary),
            ),
            const SizedBox(height: DshSpace.lg),
            action,
          ],
        ),
      ),
    );
  }
}
