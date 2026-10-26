import 'dart:async';
import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'document_controller.dart';
import 'html_document.dart';
import 'html_platform_view.dart';

class HtmlBody extends StatefulWidget {
  const HtmlBody({
    super.key,
    required this.document,
    required this.i18n,
    required this.interactive,
  });
  final DocumentController document;
  final DshI18n i18n;
  final bool interactive;
  @override
  State<HtmlBody> createState() => _HtmlBodyState();
}

class _HtmlBodyState extends State<HtmlBody> {
  int generation = 0;
  Uint8List? _packedBytes;
  bool? _packedInteractive;
  String? html;
  bool failed = false;
  final watchers = <String, StreamSubscription<WorkspaceWatchEvent>>{};
  @override
  void initState() {
    super.initState();
    unawaited(_pack());
  }

  @override
  void didUpdateWidget(HtmlBody old) {
    super.didUpdateWidget(old);
    if (!identical(_packedBytes, widget.document.bytes) ||
        _packedInteractive != widget.interactive ||
        old.document != widget.document) {
      unawaited(_pack());
    }
  }

  Future<void> _pack() async {
    final ticket = ++generation;
    for (final watcher in watchers.values.toList()) {
      unawaited(watcher.cancel());
    }
    watchers.clear();
    final document = widget.document,
        interactive = widget.interactive,
        bytes = widget.document.bytes;
    if (bytes == null) return;
    _packedBytes = bytes;
    _packedInteractive = interactive;
    bool current() => mounted && ticket == generation;
    void check() {
      if (!current()) throw StateError('HTML packing retired');
    }

    if (mounted) {
      setState(() {
        html = null;
        failed = false;
      });
    }
    void watch(String path) {
      if (!current() || watchers.containsKey(path)) return;
      watchers[path] = document.files.changes(document.sessionId, path).listen((
        event,
      ) {
        if (current() && (event is WatchChanged || event is WatchReopened)) {
          unawaited(_pack());
        }
      }, onError: (Object _) {});
    }

    try {
      final content = interactive
          ? createInteractiveHtmlDocument(
              await packHtmlDocument(bytes, (reference) async {
                final relative = htmlRelativeFile(reference);
                check();
                try {
                  final result = await document.files.readBytes(
                    document.sessionId,
                    relative,
                    baseFile: document.path,
                  );
                  check();
                  watch(result.absolutePath);
                  return result.data;
                } catch (e) {
                  if (e is RemoteException && e.details['path'] is String) {
                    watch(e.details['path'] as String);
                  }
                  rethrow;
                }
              }, checkCancelled: check),
            )
          : createBasicHtmlDocument(bytes);
      check();
      setState(
        () => html = sandboxedHtmlDocument(content, interactive: interactive),
      );
    } catch (_) {
      if (current()) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    generation++;
    for (final sub in watchers.values) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.i18n.t('documentHtml', 'failed')),
            DshButton(
              onPressed: () => unawaited(_pack()),
              child: Text(widget.i18n.t('sidebarDocumentPreview', 'retry')),
            ),
          ],
        ),
      );
    }
    final content = html;
    if (content == null) {
      return Center(child: Text(widget.i18n.t('documentHtml', 'loading')));
    }
    return Semantics(
      label: widget.i18n.t('documentHtml', 'frame'),
      child: HtmlPlatformView(
        key: ValueKey((generation, widget.interactive)),
        html: content,
        onFailure: () {
          if (mounted) setState(() => failed = true);
        },
      ),
    );
  }
}
