import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart' show DirectoryFlowOwner;
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'browser_model.dart';
import 'browser_view.dart';

/// The browse picking occupant of the two directory-flow holes (dsh
/// `BrowseDirectoryFlow`): adapts the hole's owner conversation onto the
/// browser. A confirmed directory is the picked path and dismissal is the
/// cancellation. Browse failures (an unreadable target, a create conflict)
/// stay inside the browser's own error lines, so the owner's `onError` arm is
/// never driven here.
///
/// The browser opens as dsh's dialog at every width ([showDshDialog]): 680 x 500
/// up to the room there is. The occupant itself draws nothing; the route is its
/// surface.
class BrowseDirectoryFlow extends StatefulWidget {
  const BrowseDirectoryFlow({
    super.key,
    required this.owner,
    required this.list,
    required this.create,
    required this.i18n,
    this.failureText = DirectoryBrowserModel.defaultFailureText,
  });

  final DirectoryFlowOwner owner;
  final ListDirectory list;
  final CreateDirectory create;
  final DshI18n i18n;
  final FailureText failureText;

  @override
  State<BrowseDirectoryFlow> createState() => _BrowseDirectoryFlowState();
}

class _BrowseDirectoryFlowState extends State<BrowseDirectoryFlow> {
  late DirectoryBrowserModel _model;
  final ValueNotifier<bool> _busy = ValueNotifier(false);
  Route<void>? _route;
  bool _withdrawing = false;

  @override
  void initState() {
    super.initState();
    _model = _newModel();
    _busy.value = widget.owner.busy;
    if (widget.owner.open) _scheduleOpen();
  }

  DirectoryBrowserModel _newModel() => DirectoryBrowserModel(
    list: widget.list,
    create: widget.create,
    failureText: widget.failureText,
    homeLabel: widget.i18n.t('directory-browser', 'browser.home'),
  );

  @override
  void didUpdateWidget(BrowseDirectoryFlow old) {
    super.didUpdateWidget(old);
    _model.homeLabel = widget.i18n.t('directory-browser', 'browser.home');
    // The owner rebuilds this occupant mid-frame: what touches the route or
    // notifies listeners waits for the frame to end.
    _afterFrame(() {
      if (_busy.value != widget.owner.busy) _busy.value = widget.owner.busy;
    });
    if (!old.owner.open && widget.owner.open) _scheduleOpen();
    if (old.owner.open && !widget.owner.open) {
      _afterFrame(() {
        if (!widget.owner.open) _withdraw();
      });
    }
  }

  void _afterFrame(VoidCallback fn) {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) fn();
      });
    } else {
      fn();
    }
  }

  @override
  void dispose() {
    final route = _route;
    final navigator = route?.navigator;
    _model.close();
    if (route != null && navigator != null && route.isActive) {
      _withdrawing = true;
      // Unmounting is mid-frame too; the route goes once the frame is over.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) navigator.removeRoute(route);
      });
    }
    _model.dispose();
    _busy.dispose();
    super.dispose();
  }

  void _scheduleOpen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.owner.open && _route == null) _open();
    });
  }

  void _open() {
    _model.open();
    showDshDialog<void>(
      context,
      label: widget.i18n.t('directory-browser', 'browser.title'),
      width: 680,
      // `min(500px, 100dvh - 32px)`: the room the card has, never more.
      height: 500,
      builder: (ctx) {
        _route ??= ModalRoute.of(ctx) as Route<void>?;
        return ValueListenableBuilder<bool>(
          valueListenable: _busy,
          builder: (ctx, busy, _) => DirectoryBrowserView(
            model: _model,
            i18n: widget.i18n,
            busy: busy,
            onOpen: (path) => widget.owner.onPicked(path),
            onClose: () => widget.owner.onCancel(),
          ),
        );
      },
    ).whenComplete(() {
      final dismissedByUser = !_withdrawing && _route != null;
      _route = null;
      _withdrawing = false;
      if (dismissedByUser && mounted) {
        _model.close();
        // A scrim tap, drag or Back is the cancellation.
        if (widget.owner.open) widget.owner.onCancel();
      }
    });
  }

  /// The owner withdrew the request (a pick adopted, a cancel, a dispose):
  /// close the route without reporting a second outcome.
  void _withdraw() {
    final route = _route;
    _model.close();
    if (route == null) return;
    _withdrawing = true;
    final navigator = route.navigator;
    if (navigator != null && route.isActive) navigator.removeRoute(route);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
