import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show showModalBottomSheet;
import 'package:flutter/widgets.dart';

import 'document_bodies.dart';
import 'document_controller.dart';
import 'download.dart';
import 'renderers.dart';

/// The text of one failed read, in terms of the file (dsh `failureLine`).
String failureLine(DshI18n i18n, Object failure) {
  String t(String key, [Map<String, Object?> params = const {}]) =>
      i18n.t('sidebarDocumentPreview', key, params: params);
  if (failure is RemoteException) {
    switch (failure.code) {
      case 'workspace-file/not-found':
        return t('error.notFound');
      case 'workspace-file/too-large':
        final limit = failure.details['limit'];
        return t('error.tooLarge', {
          'limit': limit is int ? humanBytes(limit) : '?',
        });
      case 'workspace-file/not-text':
        return t('error.notText');
      case 'workspace-file/not-regular-file':
        return t('error.notRegularFile');
    }
    return t('error.unavailable', {'message': failure.message});
  }
  return t('error.unavailable', {'message': '$failure'});
}

/// dsh `humanBytes`.
String humanBytes(int bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).round()} MB';
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}

/// What an empty preview offers beside its failure line (dsh
/// `emptyFailureRecourse`): hand a readable file this preview cannot show to
/// the system, nothing for a path with nothing to show, a retry otherwise.
enum EmptyRecourse { open, retry, none }

EmptyRecourse emptyFailureRecourse(Object failure) {
  if (failure is RemoteException) {
    switch (failure.code) {
      case 'workspace-file/not-text':
      case 'workspace-file/too-large':
        return EmptyRecourse.open;
      case 'workspace-file/not-found':
      case 'workspace-file/not-regular-file':
        return EmptyRecourse.none;
    }
  }
  return EmptyRecourse.retry;
}

/// A file tab's body (dsh `TextPreview`): the path with the viewer, wrap and
/// reload controls, then the content in the selected viewer, or the reason it
/// is not showing.
class DocumentView extends StatefulWidget {
  const DocumentView({super.key, required this.owner, required this.i18n});

  final SidebarTabOwner owner;
  final DshI18n i18n;

  @override
  State<DocumentView> createState() => _DocumentViewState();
}

class _DocumentViewState extends State<DocumentView> {
  DocumentController? _controller;
  FileDownload? _download;
  FileAddress? _address;

  @override
  void initState() {
    super.initState();
    final address = parseSessionFileAddress(widget.owner.contentId);
    final files = widget.owner.session.files;
    _address = address;
    if (address != null && files != null) {
      _controller = DocumentController(
        sessionId: address.sessionId,
        path: address.path,
        files: files.remote,
      )..navigate(widget.owner.line, widget.owner.revision);
    }
  }

  @override
  void didUpdateWidget(DocumentView old) {
    super.didUpdateWidget(old);
    _controller?.navigate(widget.owner.line, widget.owner.revision);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _download?.dispose();
    super.dispose();
  }

  String _t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t('sidebarDocumentPreview', key, params: params);

  FileDownload? _downloadOf(String name) {
    final files = widget.owner.session.files;
    final actions = files?.actions;
    final address = _address;
    if (files == null || actions == null || address == null) return null;
    return _download ??= FileDownload(
      sessionId: address.sessionId,
      path: address.path,
      name: name,
      files: files.remote,
      actions: actions,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final controller = _controller;
    if (controller == null) {
      return Center(
        key: const ValueKey('document-unavailable'),
        child: DshChromeText(
          _t('resourceUnavailable'),
          style: theme
              .textStyle('--dsw-font-s-14')
              .copyWith(color: theme.labelSecondary),
        ),
      );
    }
    final path = _address!.path;
    final name = pathPartsOf(controller.absolutePath ?? path).name;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final selected = controller.selected;
        return Column(
          key: ValueKey('document-${widget.owner.contentId}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              path: controller.absolutePath ?? path,
              i18n: widget.i18n,
              controller: controller,
              home: widget.owner.session.hostHome,
              onViewer: () => _chooseViewer(context, controller),
            ),
            if (controller.metaFailure != null && controller.hasContent)
              _Bar(
                key: const ValueKey('document-meta-failed'),
                text: failureLine(widget.i18n, controller.metaFailure!),
                action: _t('reloadNow'),
                onAction: controller.reload,
              ),
            Expanded(child: _body(context, controller, selected, name)),
          ],
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    DocumentController c,
    DocumentRenderer? selected,
    String name,
  ) {
    if (selected == null) {
      // A known binary container: no read, the unsupported line and the
      // actions that hand the file to the system.
      return _EmptyState(
        key: const ValueKey('document-unsupported'),
        path: name,
        line: _t('unsupportedFile'),
        children: [_actions(name)],
      );
    }
    if (c.failure != null && !c.hasContent) {
      final recourse = emptyFailureRecourse(c.failure!);
      return _EmptyState(
        key: const ValueKey('document-failed'),
        path: name,
        line: failureLine(widget.i18n, c.failure!),
        children: [
          if (recourse == EmptyRecourse.open) _actions(name),
          if (recourse == EmptyRecourse.retry)
            _TextButton(
              key: const ValueKey('document-retry'),
              label: _t('retry'),
              onTap: c.reload,
            ),
        ],
      );
    }
    if (!c.hasContent) {
      return Center(
        key: const ValueKey('document-loading'),
        child: _Loading(label: _t('loading')),
      );
    }
    return DocumentBody(
      controller: c,
      renderer: selected,
      i18n: widget.i18n,
      name: name,
      footer: _footer(c),
    );
  }

  Widget? _footer(DocumentController c) {
    if (c.selected?.loading != DocumentLoad.textPages) return null;
    if (c.failure != null) {
      return Padding(
        key: const ValueKey('document-page-failed'),
        padding: const EdgeInsets.all(DshSpace.md),
        child: Row(
          children: [
            Expanded(
              child: DshChromeText(
                failureLine(widget.i18n, c.failure!),
                style: _small(context),
              ),
            ),
            _TextButton(label: _t('retry'), onTap: c.loadNext),
          ],
        ),
      );
    }
    if (c.eof) return null;
    return Padding(
      key: const ValueKey('document-more'),
      padding: const EdgeInsets.all(DshSpace.md),
      child: Center(
        child: c.loading
            ? _Loading(label: _t('loading'), inline: true)
            : _TextButton(label: _t('loadMore'), onTap: c.loadNext),
      ),
    );
  }

  TextStyle _small(BuildContext context) {
    final theme = context.dsh;
    return theme
        .textStyle('--dsw-font-xs-13')
        .copyWith(color: theme.labelSecondary);
  }

  Widget _actions(String name) {
    final download = _downloadOf(name);
    if (download == null) return const SizedBox.shrink();
    return _FileActions(download: download, i18n: widget.i18n);
  }

  Future<void> _chooseViewer(BuildContext context, DocumentController c) async {
    final theme = context.dsh;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: theme.color('--dsw-alias-bg-layer-2'),
      builder: (sheet) => SafeArea(
        child: Column(
          key: const ValueKey('viewer-sheet'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(DshSpace.lg),
              child: Align(
                alignment: Alignment.centerLeft,
                child: DshChromeText(
                  _t('openWith'),
                  style: theme
                      .textStyle('--dsw-font-xs-13')
                      .copyWith(color: theme.labelSecondary),
                ),
              ),
            ),
            for (final r in c.candidates)
              GestureDetector(
                key: ValueKey('viewer-${r.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(sheet).pop(r.id),
                child: SizedBox(
                  height: DshSpace.touch,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DshSpace.lg,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: DshChromeText(
                            widget.i18n.t(r.titleNamespace, r.titleKey),
                            style: theme
                                .textStyle('--dsw-font-base-16')
                                .copyWith(
                                  color: r.id == c.selected?.id
                                      ? theme.color('--dsw-alias-brand-primary')
                                      : theme.labelPrimary,
                                ),
                          ),
                        ),
                        if (r.id == c.selected?.id)
                          DshIcon(
                            DshIcons.check,
                            size: 16,
                            color: theme.color('--dsw-alias-brand-primary'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) c.select(chosen);
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.path,
    required this.i18n,
    required this.controller,
    required this.home,
    required this.onViewer,
  });

  final String path;
  final DshI18n i18n;
  final DocumentController controller;
  final String home;
  final VoidCallback onViewer;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    String t(String key) => i18n.t('sidebarDocumentPreview', key);
    final selected = controller.selected;
    final parts = pathPartsOf(_abbrev(path, home));
    Widget tool(Key key, DshIconData icon, String label, VoidCallback onTap) =>
        Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox(
              width: DshSpace.touch,
              height: DshSpace.touch,
              child: Center(
                child: DshIcon(icon, size: 16, color: theme.labelSecondary),
              ),
            ),
          ),
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.color('--dsw-alias-border-l3'),
            width: dshHairline,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: DshSpace.lg),
        child: SizedBox(
          height: DshSpace.touch,
          child: Row(
            children: [
              Expanded(
                child: Row(
                  key: const ValueKey('document-path'),
                  children: [
                    Flexible(
                      child: DshChromeText(
                        parts.directory,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme
                            .textStyle('--dsw-font-xs-13')
                            .copyWith(
                              color: theme.color('--dsw-alias-label-tertiary'),
                            ),
                      ),
                    ),
                    DshChromeText(
                      parts.name,
                      maxLines: 1,
                      style: theme
                          .textStyle('--dsw-font-xs-13')
                          .copyWith(color: theme.labelPrimary),
                    ),
                  ],
                ),
              ),
              if (controller.candidates.length > 1 && selected != null)
                GestureDetector(
                  key: const ValueKey('viewer-menu'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onViewer,
                  child: Semantics(
                    button: true,
                    label: t('openWith'),
                    child: SizedBox(
                      height: DshSpace.touch,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: DshSpace.sm,
                          ),
                          child: DshChromeText(
                            i18n.t(selected.titleNamespace, selected.titleKey),
                            style: theme
                                .textStyle('--dsw-font-xs-13')
                                .copyWith(color: theme.labelSecondary),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (selected?.wrap ?? false)
                tool(
                  const ValueKey('document-wrap'),
                  controller.wrap ? DshIcons.nowrap : DshIcons.wrap,
                  t(controller.wrap ? 'wrap.disable' : 'wrap.enable'),
                  controller.toggleWrap,
                ),
              tool(
                const ValueKey('document-reload'),
                DshIcons.refresh,
                t('reload'),
                controller.reload,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _abbrev(String path, String home) {
    if (home.isEmpty || path.contains(r'\')) return path;
    final root = home.replaceAll(RegExp(r'/+$'), '');
    if (root.isEmpty) return path;
    if (path.replaceAll(RegExp(r'/+$'), '') == root) return '~';
    if (path.startsWith('$root/')) return '~${path.substring(root.length)}';
    return path;
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    super.key,
    required this.text,
    required this.action,
    required this.onAction,
  });

  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Container(
      color: theme.color('--dsw-alias-bg-layer-2'),
      padding: const EdgeInsets.symmetric(
        horizontal: DshSpace.md,
        vertical: DshSpace.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: DshChromeText(
              text,
              style: theme
                  .textStyle('--dsw-font-xxs-12')
                  .copyWith(color: theme.labelSecondary),
            ),
          ),
          _TextButton(label: action, onTap: onAction),
        ],
      ),
    );
  }
}

class _TextButton extends StatelessWidget {
  const _TextButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36, minWidth: 44),
          child: Center(
            widthFactor: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DshSpace.sm),
              child: ExcludeSemantics(
                child: DshChromeText(
                  label,
                  style: theme
                      .textStyle('--dsw-font-s-14')
                      .copyWith(
                        color: theme.color('--dsw-alias-brand-primary'),
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.label, this.inline = false});
  final String label;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DshSpinner(size: 16, color: theme.color('--dsw-alias-label-tertiary')),
        const SizedBox(width: DshSpace.sm),
        DshChromeText(
          label,
          style: theme
              .textStyle('--dsw-font-xs-13')
              .copyWith(color: theme.color('--dsw-alias-label-tertiary')),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    super.key,
    required this.path,
    required this.line,
    required this.children,
  });

  final String path;
  final String line;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DshSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DshFileTypeIcon(path: path, size: 36),
            const SizedBox(height: DshSpace.md),
            DshChromeText(
              line,
              textAlign: TextAlign.center,
              style: theme
                  .textStyle('--dsw-font-s-14')
                  .copyWith(color: theme.labelSecondary),
            ),
            for (final c in children) ...[
              const SizedBox(height: DshSpace.md),
              c,
            ],
          ],
        ),
      ),
    );
  }
}

/// Open and save for a file this preview cannot draw: downloads it to the
/// device first, with progress.
class _FileActions extends StatefulWidget {
  const _FileActions({required this.download, required this.i18n});

  final FileDownload download;
  final DshI18n i18n;

  @override
  State<_FileActions> createState() => _FileActionsState();
}

class _FileActionsState extends State<_FileActions> {
  String? _note;

  String _a(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t(appNamespace, key, params: params);

  Future<void> _run(Future<bool> Function() action) async {
    setState(() => _note = null);
    final ok = await action();
    if (!mounted) return;
    final error = widget.download.error;
    setState(() {
      _note = error != null
          ? _a('file.downloadFailed', {
              'message': error is RemoteException ? error.message : '$error',
            })
          : ok
          ? null
          : _a('file.cannotOpen');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final d = widget.download;
    final actions = d.actions;
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (d.busy)
            DshChromeText(
              key: const ValueKey('download-progress'),
              _a('file.downloading', {
                'percent': ((d.fraction ?? 0) * 100).round(),
              }),
              style: theme
                  .textStyle('--dsw-font-xs-13')
                  .copyWith(color: theme.labelSecondary),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (actions.canOpen)
                  DshButton(
                    key: const ValueKey('file-open'),
                    variant: DshButtonVariant.primary,
                    onPressed: () => _run(d.open),
                    child: DshChromeText(_a('file.open')),
                  ),
                if (actions.canOpen && actions.canSave)
                  const SizedBox(width: DshSpace.sm),
                if (actions.canSave)
                  DshButton(
                    key: const ValueKey('file-save'),
                    variant: DshButtonVariant.outline,
                    onPressed: () => _run(d.save),
                    child: DshChromeText(_a('file.save')),
                  ),
              ],
            ),
          if (_note != null)
            Padding(
              padding: const EdgeInsets.only(top: DshSpace.sm),
              child: DshChromeText(
                _note!,
                key: const ValueKey('download-note'),
                textAlign: TextAlign.center,
                style: theme
                    .textStyle('--dsw-font-xxs-12')
                    .copyWith(
                      color: theme.color('--dsw-alias-state-error-primary'),
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
