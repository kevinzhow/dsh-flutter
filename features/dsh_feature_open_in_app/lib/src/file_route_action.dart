import 'dart:async';
import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

class FileRouteAction extends StatefulWidget {
  const FileRouteAction({super.key, required this.owner, required this.i18n});
  final DeliverablesFileActionsOwner owner;
  final DshI18n i18n;
  @override
  State<FileRouteAction> createState() => _RouteState();
}

class _RouteState extends State<FileRouteAction> {
  FileApplicationsHandle? handle;
  final toasts = DshToasts();
  @override
  void initState() {
    super.initState();
    bind();
  }

  @override
  void didUpdateWidget(FileRouteAction old) {
    super.didUpdateWidget(old);
    if (old.owner.actionUrl != widget.owner.actionUrl ||
        old.owner.available != widget.owner.available) {
      unbind(old.owner);
      bind();
    }
  }

  void bind() {
    if (widget.owner.available) handle = widget.owner.acquireApplications();
  }

  void unbind(DeliverablesFileActionsOwner owner) {
    if (handle case final h?) owner.releaseApplications(h);
    handle = null;
  }

  @override
  void dispose() {
    unbind(widget.owner);
    toasts.dismiss();
    super.dispose();
  }

  String t(String key, [Map<String, Object?> p = const {}]) =>
      widget.i18n.t('open-in-app', key, params: p);
  Future<void> act(NativeFileAction action, [String? app]) async {
    final failure = await widget.owner.onAction(action, app);
    if (failure != null && mounted) {
      toasts.show(
        context,
        t(
          failure == NativeOpenFailure.revealError
              ? 'path.revealError'
              : 'path.openError',
        ),
        icon: DshIcons.warning,
      );
    }
  }

  Widget icon(NativeFileApplication? app) {
    final raw = app?.icon;
    if (raw == null || !raw.startsWith('data:image/png;base64,')) {
      return const DshIcon(DshIcons.rightUp, size: 13);
    }
    return Image.memory(
      base64Decode(raw.substring(raw.indexOf(',') + 1)),
      width: 14,
      height: 14,
      errorBuilder: (_, _, _) => const DshIcon(DshIcons.rightUp, size: 13),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = handle;
    if (!widget.owner.available || h == null) return const SizedBox.shrink();
    return DshWatch(
      changes: h.state.changes,
      builder: (_) {
        final value = h.state.value,
            apps = value.value ?? const <NativeFileApplication>[],
            preferred =
                apps.where((a) => a.isDefault).firstOrNull ?? apps.firstOrNull;
        final busy =
            widget.owner.pending || value.phase == HostReadPhase.loading;
        final label = preferred == null
            ? t('path.reveal')
            : t('open.title', {'app': preferred.name});
        void primary() {
          if (preferred == null) {
            unawaited(act(NativeFileAction.reveal));
          } else {
            unawaited(
              act(
                NativeFileAction.open,
                preferred.isDefault ? null : preferred.id,
              ),
            );
          }
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DshButton(
              size: DshButtonSize.sm,
              semanticLabel: label,
              onPressed: busy ? null : primary,
              child: preferred == null
                  ? const DshIcon(DshIcons.folderOpen, size: 13)
                  : icon(preferred),
            ),
            DshMenu(
              dense: true,
              entries: [
                if (value.phase == HostReadPhase.error)
                  DshMenuItem('refresh', t('path.appsError')),
                for (final app in apps)
                  DshMenuItem(
                    'app:${app.id}',
                    app.isDefault
                        ? t('path.appDefault', {'app': app.name})
                        : app.name,
                  ),
                DshMenuItem('reveal', t('path.reveal')),
              ],
              onSelect: (id) {
                if (id == 'refresh') {
                  h.refresh();
                } else if (id == 'reveal') {
                  unawaited(act(NativeFileAction.reveal));
                } else {
                  unawaited(act(NativeFileAction.open, id.substring(4)));
                }
              },
              builder: (context, menu) => DshButton(
                size: DshButtonSize.sm,
                semanticLabel: t('path.more'),
                onPressed: busy ? null : menu.toggle,
                child: const DshIcon(DshIcons.chevronDown, size: 12),
              ),
            ),
          ],
        );
      },
    );
  }
}
