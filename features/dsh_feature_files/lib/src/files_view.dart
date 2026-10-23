import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'files_controller.dart';

/// The file tree tab's body (dsh `FilesBody`): the workspace root and whatever
/// the person opened under it. A directory toggles, a file opens in the
/// preview, anything else is shown but refuses to open.
class FilesView extends StatefulWidget {
  const FilesView({super.key, required this.owner, required this.i18n});

  final SidebarTabOwner owner;
  final DshI18n i18n;

  @override
  State<FilesView> createState() => _FilesViewState();
}

class _FilesViewState extends State<FilesView> {
  FilesController? _controller;

  SessionOwner get _session => widget.owner.session;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  /// The root is the session's workspace; it is known once the list carries it.
  void _bind() {
    final cwd = _session.cwd;
    final files = _session.files;
    if (cwd == null || cwd.isEmpty || files == null || _controller != null) {
      return;
    }
    _controller = FilesController(
      sessionId: _session.sessionId,
      root: cwd,
      files: files.remote,
    );
  }

  @override
  void didUpdateWidget(FilesView old) {
    super.didUpdateWidget(old);
    _bind();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t('sidebarFiles', key, params: params);

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    _bind();
    final controller = _controller;
    if (controller == null) {
      return Center(
        key: const ValueKey('files-no-workspace'),
        child: Padding(
          padding: const EdgeInsets.all(DshSpace.xl),
          child: Text(
            _t('noWorkspace'),
            textAlign: TextAlign.center,
            style: theme
                .textStyle('--dsw-font-s-14')
                .copyWith(color: theme.labelSecondary),
          ),
        ),
      );
    }
    final home = _session.hostHome;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        key: const ValueKey('files-tree'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            path: abbreviateHome(controller.root, home),
            reloadLabel: _t('reload'),
            onReload: controller.reload,
          ),
          Expanded(
            child: ListView(
              key: const ValueKey('files-list'),
              padding: const EdgeInsets.only(bottom: DshSpace.xl),
              children: _rows(context, controller),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _rows(BuildContext context, FilesController c) {
    final rows = <Widget>[];
    void level(String path, int depth) {
      final state = c.levels[path];
      if (state == null || state is FilesLevelLoading) {
        rows.add(_Note(text: _t('loading'), depth: depth, id: 'loading'));
        return;
      }
      if (state is FilesLevelFailed) {
        rows.add(
          _Note(
            text: _failure(state.failure),
            depth: depth,
            id: 'failed',
            error: true,
          ),
        );
        return;
      }
      final loaded = state as FilesLevelLoaded;
      if (loaded.failure != null) {
        rows.add(
          _Note(
            text: _failure(loaded.failure!),
            depth: depth,
            id: 'failed',
            error: true,
          ),
        );
      }
      final entries = orderEntries(loaded.entries);
      if (entries.isEmpty) {
        rows.add(_Note(text: _t('empty'), depth: depth, id: 'empty'));
      }
      for (final entry in entries) {
        final child = childPath(path, entry.name);
        switch (entry.type) {
          case WorkspaceEntryType.directory:
            final open = c.expanded.contains(child);
            rows.add(
              _Row(
                key: ValueKey('dir-$child'),
                depth: depth,
                name: entry.name,
                icon: DshIcon(
                  open ? DshIcons.folderOpen : DshIcons.folderClose,
                  size: 16,
                  color: context.dsh.color('--dsw-static-amber-400'),
                ),
                expanded: open,
                onTap: () => c.toggle(child),
              ),
            );
            if (open) level(child, depth + 1);
          case WorkspaceEntryType.file:
            rows.add(
              _Row(
                key: ValueKey('file-$child'),
                depth: depth,
                name: entry.name,
                icon: DshFileTypeIcon(path: entry.name, size: 16),
                onTap: () => widget.owner.actions.openResource(
                  fileAddressFor(c.sessionId, c.root, child),
                ),
              ),
            );
          case WorkspaceEntryType.other:
            rows.add(
              _Row(
                key: ValueKey('other-$child'),
                depth: depth,
                name: entry.name,
                icon: const SizedBox(width: 16, height: 16),
                disabledHint: _t('entry.other'),
              ),
            );
        }
      }
      if (loaded.truncated) {
        rows.add(_Note(text: _t('truncated'), depth: depth, id: 'truncated'));
      }
    }

    level(c.root, 0);
    return rows;
  }

  String _failure(Object error) {
    if (error is RemoteException) {
      switch (error.code) {
        case 'workspace-file/not-found':
          return _t('error.notFound');
        case 'workspace-file/outside-workspace':
          return _t('error.outsideWorkspace');
        case 'workspace-file/not-directory':
          return _t('error.notDirectory');
      }
      return _t('error.unavailable', {'message': error.message});
    }
    return _t('error.unavailable', {'message': '$error'});
  }
}

/// `~` for the host home (dsh `abbreviateHomePath`).
String abbreviateHome(String path, String home) {
  if (home.isEmpty || path.contains(r'\')) return path;
  final root = home.replaceAll(RegExp(r'/+$'), '');
  if (root.isEmpty) return path;
  if (path.replaceAll(RegExp(r'/+$'), '') == root) return '~';
  if (path.startsWith('$root/')) return '~${path.substring(root.length)}';
  return path;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.path,
    required this.reloadLabel,
    required this.onReload,
  });

  final String path;
  final String reloadLabel;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Padding(
      padding: const EdgeInsets.only(left: DshSpace.lg),
      child: SizedBox(
        height: DshSpace.touch,
        child: Row(
          children: [
            Expanded(
              child: Text(
                path,
                key: const ValueKey('files-root'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                style: theme
                    .textStyle('--dsw-font-xs-13')
                    .copyWith(color: theme.labelSecondary),
              ),
            ),
            Semantics(
              button: true,
              label: reloadLabel,
              child: GestureDetector(
                key: const ValueKey('files-reload'),
                behavior: HitTestBehavior.opaque,
                onTap: onReload,
                child: SizedBox(
                  width: DshSpace.touch,
                  height: DshSpace.touch,
                  child: Center(
                    child: DshIcon(
                      DshIcons.refresh,
                      size: 16,
                      color: theme.labelSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.depth,
    required this.name,
    required this.icon,
    this.expanded,
    this.onTap,
    this.disabledHint,
  });

  final int depth;
  final String name;
  final Widget icon;
  final bool? expanded;
  final VoidCallback? onTap;
  final String? disabledHint;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final disabled = onTap == null;
    return Semantics(
      button: !disabled,
      enabled: !disabled,
      expanded: expanded,
      label: name,
      hint: disabledHint,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: EdgeInsets.only(
              left: DshSpace.lg + depth * DshSpace.lg,
              right: DshSpace.lg,
            ),
            child: Row(
              children: [
                icon,
                const SizedBox(width: DshSpace.sm),
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme
                          .textStyle('--dsw-font-s-14')
                          .copyWith(
                            color: disabled
                                ? theme.color('--dsw-alias-label-tertiary')
                                : theme.labelPrimary,
                          ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({
    required this.text,
    required this.depth,
    required this.id,
    this.error = false,
  });

  final String text;
  final int depth;
  final String id;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Padding(
      key: ValueKey('note-$id'),
      padding: EdgeInsets.fromLTRB(
        DshSpace.lg + depth * DshSpace.lg + 24,
        DshSpace.xs,
        DshSpace.lg,
        DshSpace.xs,
      ),
      child: Text(
        text,
        style: theme
            .textStyle('--dsw-font-xs-13')
            .copyWith(
              color: error
                  ? theme.color('--dsw-alias-state-error-primary')
                  : theme.color('--dsw-alias-label-tertiary'),
            ),
      ),
    );
  }
}
