/// The shortcut service (dsh `shortcuts/src/client/index.ts`): the registry
/// plus the preference store behind it. One per window; the adapter that turns
/// platform key events into gestures lives in the Flutter feature.
library;

import 'dart:async';

import 'binding.dart';
import 'configuration.dart';
import 'persistence.dart';
import 'registry.dart';

/// The stack of modal layers the keyboard adapter reads (dsh reads the top
/// `data-shortcut-modal` of the document): features push the id of a modal they
/// show (`settings`, `shortcuts`, `shortcut-edit`, ...) and pop it on close.
class ModalStack {
  final List<String> _ids = [];

  /// The id of the top modal, or null when none is open.
  String? get top => _ids.isEmpty ? null : _ids.last;

  /// Open a modal layer; returns the disposer that removes exactly this one.
  void Function() push(String id) {
    _ids.add(id);
    var done = false;
    return () {
      if (done) return;
      done = true;
      _ids.remove(id);
    };
  }
}

/// Feature-facing keyboard service.
class ShortcutService {
  ShortcutService({
    required this.runtime,
    required this.platform,
    required ShortcutStorage storage,
    bool rereadBeforeWrite = false,
    this.stopSequenceMs = 500,
  }) : registry = ShortcutRegistry(runtime, platform, initialShortcutConfig()) {
    _persistence = ShortcutPersistence(
      storage,
      runtime,
      platform,
      rereadBeforeWrite,
      _publish,
    );
  }

  final ShortcutRuntime runtime;
  final ShortcutPlatform platform;
  final ShortcutRegistry registry;

  /// Maximum interval between independent Escape presses for stopping a reply.
  final int stopSequenceMs;

  /// The open modal layers.
  final ModalStack modals = ModalStack();

  late final ShortcutPersistence _persistence;
  bool _active = true;
  bool _connected = false;

  void _publish(ShortcutConfigSnapshot snapshot) {
    if (_active &&
        _connected &&
        snapshot.sequence >= registry.config.sequence) {
      registry.configure(snapshot);
    }
  }

  /// Effective localized rows.
  List<ShortcutCatalogEntry> get catalog => registry.catalog;

  /// Accepted preferences and read diagnostics.
  ShortcutConfigSnapshot get config => registry.config;

  /// Fixed rows of the reference.
  List<ShortcutFixedCatalogEntry> get fixedCatalog =>
      registry.fixedCatalog.value;

  /// Subscribe to catalog and configuration changes; returns the disposer.
  void Function() subscribe(void Function() listener) =>
      registry.subscribe(listener);

  /// Subscribe to the fixed rows; returns the disposer.
  void Function() subscribeFixed(void Function() listener) =>
      registry.fixedCatalog.subscribe(listener);

  /// Read the stored preferences and enable the commands (dsh does this on
  /// construction through the first catalog sync).
  Future<void> start() => _syncDefinitions();

  /// Register a command; duplicate ids and overlapping default bindings throw.
  void Function() register(ShortcutCommand command) {
    final off = registry.register(command);
    unawaited(_syncDefinitions());
    return () {
      off();
      unawaited(_syncDefinitions());
    };
  }

  /// Contribute one fixed action and reserve its keys against editable bindings.
  void Function() registerFixed(ShortcutFixedCommand command) {
    final off = registry.registerFixed(command);
    unawaited(_syncDefinitions());
    return () {
      off();
      unawaited(_syncDefinitions());
    };
  }

  /// Re-resolve labels after a locale change.
  void refreshLabels() => registry.refreshLabels();

  /// Describe a candidate using the device's rules (see
  /// [ShortcutRegistry.describeBinding]); invalid codes throw.
  ({
    NormalizedBinding? binding,
    List<String> keys,
    BindingIssue? issue,
    List<String> conflicts,
  })
  describeBinding(ShortcutBinding? binding) =>
      registry.describeBinding(binding);

  Future<void> _syncDefinitions() async {
    if (!_active) return;
    _persistence.setDefinitions(registry.definitions());
    try {
      final snapshot = await _persistence.readCurrent();
      _connected = true;
      if (_active && snapshot.sequence >= registry.config.sequence) {
        registry.configure(snapshot);
      }
    } on Object {
      _failRead();
    }
  }

  void _failRead() {
    if (_active) {
      registry.configure(
        registry.config.copyWith(
          status: ShortcutConfigStatus.unreadable,
          error: ShortcutReadError.read,
        ),
      );
    }
  }

  /// Persist one reviewed operation while retaining accepted bindings on
  /// failure. The classified outcome and the accepted snapshot.
  Future<ShortcutSaveResult> edit(ShortcutEdit edit, String revision) async {
    ShortcutSaveResult result;
    try {
      result = await _persistence.edit(edit, revision);
    } on Object {
      return ShortcutSaveResult(
        ShortcutSaveStatus.writeFailed,
        registry.config,
      );
    }
    if (_active && result.snapshot.sequence >= registry.config.sequence) {
      registry.configure(result.snapshot);
    }
    return result;
  }

  /// Invoke a native menu selection independently of its optional key binding.
  void invoke(String id, ShortcutContext context) =>
      registry.invoke(id, context);

  /// Dispatch one keyboard gesture.
  ShortcutDispatch dispatch(
    ShortcutGesture gesture,
    ShortcutContext context,
    void Function() consume,
  ) => registry.dispatch(gesture, context, consume);

  /// Stop publishing and accepting edits.
  void dispose() {
    _active = false;
    _persistence.dispose();
  }
}
