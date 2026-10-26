import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Isolated browser with no application JS handlers, Host URL or credential.
/// Linux embeds WebKitGTK directly into the same native Wayland window.
class HtmlPlatformView extends StatelessWidget {
  const HtmlPlatformView({
    super.key,
    required this.html,
    required this.onFailure,
  });
  final String html;
  final VoidCallback onFailure;
  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return _LinuxHtmlView(html: html, onFailure: onFailure);
    }
    return InAppWebView(
      key: ValueKey(html),
      initialData: InAppWebViewInitialData(
        data: html,
        baseUrl: WebUri('about:blank'),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useHybridComposition: false,
        allowFileAccess: false,
        allowContentAccess: false,
        allowFileAccessFromFileURLs: false,
        allowUniversalAccessFromFileURLs: false,
        javaScriptCanOpenWindowsAutomatically: false,
        useShouldOverrideUrlLoading: true,
        isInspectable: false,
      ),
      shouldOverrideUrlLoading: (_, navigation) async {
        final scheme = navigation.request.url?.scheme;
        return const ['about', 'blob', 'data'].contains(scheme)
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL;
      },
      onPermissionRequest: (_, request) async => PermissionResponse(
        resources: request.resources,
        action: PermissionResponseAction.DENY,
      ),
      onCreateWindow: (_, _) async => false,
      onReceivedError: (_, request, error) {
        if (request.isForMainFrame == true) onFailure();
      },
      onDownloadStartRequest: (_, _) {},
    );
  }
}

class _HtmlChannel {
  static const channel = MethodChannel('app.kevinzhow.whalee/html');
  static final failures = <int, VoidCallback>{};
  static int next = 0;
  static bool initialized = false;
  static void initialize() {
    if (initialized) return;
    initialized = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'failed' && call.arguments is int) {
        failures[call.arguments]?.call();
      }
    });
  }
}

class _LinuxHtmlView extends StatefulWidget {
  const _LinuxHtmlView({required this.html, required this.onFailure});
  final String html;
  final VoidCallback onFailure;
  @override
  State<_LinuxHtmlView> createState() => _LinuxHtmlViewState();
}

class _LinuxHtmlViewState extends State<_LinuxHtmlView> {
  final position = GlobalKey();
  final id = ++_HtmlChannel.next;
  bool created = false, failed = false, scheduled = false, visible = true;
  Rect? last;
  @override
  void initState() {
    super.initState();
    _HtmlChannel.initialize();
    _HtmlChannel.failures[id] = _failure;
    unawaited(_create());
  }

  Future<void> _create() async {
    try {
      await _HtmlChannel.channel.invokeMethod<void>('create', {
        'id': id,
        'html': widget.html,
      });
      created = true;
      if (!mounted) {
        await _HtmlChannel.channel.invokeMethod<void>('dispose', {'id': id});
        return;
      }
      _schedule();
    } catch (_) {
      _failure();
    }
  }

  void _failure() {
    if (mounted && !failed) {
      failed = true;
      widget.onFailure();
    }
  }

  void _schedule() {
    if (scheduled) return;
    scheduled = true;
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduled = false;
      if (!mounted || !created) return;
      final object = position.currentContext?.findRenderObject();
      var rect = Rect.zero;
      if (visible && object is RenderBox && object.hasSize) {
        rect = object.localToGlobal(Offset.zero) & object.size;
      }
      if (last == rect) return;
      last = rect;
      unawaited(
        _HtmlChannel.channel
            .invokeMethod<void>('bounds', {
              'id': id,
              'x': rect.left,
              'y': rect.top,
              'width': rect.width,
              'height': rect.height,
            })
            .catchError((Object _) => _failure()),
      );
    });
  }

  @override
  void dispose() {
    _HtmlChannel.failures.remove(id);
    if (created) {
      unawaited(
        _HtmlChannel.channel
            .invokeMethod<void>('dispose', {'id': id})
            .catchError((Object _) {}),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    _schedule();
    return LayoutBuilder(
      builder: (context, _) {
        _schedule();
        return SizedBox.expand(key: position);
      },
    );
  }
}
