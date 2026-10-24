/// Command registration, normalized default bindings, and synchronous dispatch
/// (dsh `shortcuts/src/client/registry.ts` and `types.ts`). Adapters own the
/// event listeners (in Whalee: the keyboard adapter of `dsh_feature_shortcuts`),
/// feature packages own the actions.
library;

import 'binding.dart';
import 'configuration.dart';
import 'persistence.dart';

/// A cached current value with synchronous change notification (dsh's
/// `ObservableSnapshot`).
class SnapshotStore<T> {
  SnapshotStore(T initial) : _value = initial;

  T _value;
  final Set<void Function()> _listeners = {};

  T get value => _value;

  void set(T next) {
    _value = next;
    for (final listener in [..._listeners]) {
      listener();
    }
  }

  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

/// Local input owner resolved before an application command.
enum ShortcutRegion { page, editable, terminal }

/// Where an invocation came from.
enum ShortcutSource { keyboard, menu }

/// Synchronous input context; owners capture business targets in `resolve`.
class ShortcutContext {
  const ShortcutContext({
    required this.region,
    this.modal,
    this.target,
    this.source,
  });

  final ShortcutSource? source;
  final ShortcutRegion region;

  /// The identifier of the top modal layer, or null.
  final String? modal;

  /// Original input target, or null when none is available.
  final Object? target;

  ShortcutContext withSource(ShortcutSource source) => ShortcutContext(
    region: region,
    modal: modal,
    target: target,
    source: source,
  );
}

/// A resolved action captures its target; failures remain the owner's responsibility.
sealed class ShortcutResolution {
  const ShortcutResolution();
}

class ShortcutHandled extends ShortcutResolution {
  const ShortcutHandled(this.run);

  final void Function() run;
}

class ShortcutBlocked extends ShortcutResolution {
  const ShortcutBlocked(this.reason);

  final String reason;
}

class ShortcutPass extends ShortcutResolution {
  const ShortcutPass();
}

/// One command's labels, defaults, input ownership, and target resolver.
class ShortcutCommand {
  const ShortcutCommand({
    required this.id,
    required this.label,
    this.aliases = const [],
    required this.defaults,
    this.regions = const [ShortcutRegion.page, ShortcutRegion.editable],
    this.modals = const [],
    required this.resolve,
  });

  final String id;
  final String Function() label;
  final List<String> aliases;
  final Map<String, ShortcutBinding> defaults;
  final List<ShortcutRegion> regions;

  /// Allowed modal identifiers for non-priority keyboard input and explicit
  /// menu actions; Windows/macOS desktop keyboard bindings take priority.
  final List<String> modals;
  final ShortcutResolution Function(ShortcutContext context) resolve;
}

/// A localized, effective catalog row shared by the reference, tooltips and controls.
class ShortcutCatalogEntry {
  const ShortcutCatalogEntry({
    required this.id,
    required this.label,
    required this.aliases,
    required this.keys,
    required this.aria,
    required this.binding,
    required this.modified,
    required this.conflicts,
    required this.issue,
  });

  final String id;
  final String label;
  final List<String> aliases;
  final List<String> keys;
  final String? aria;
  final NormalizedBinding? binding;
  final bool modified;
  final List<String> conflicts;
  final BindingIssue? issue;
}

/// Keyboard adapter input, with composition and local consumption already resolved.
class ShortcutGesture {
  const ShortcutGesture({
    required this.code,
    this.secondCode,
    this.control = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
    this.repeat = false,
    this.composing = false,
    this.defaultPrevented = false,
  });

  final String code;

  /// Second physical key currently held with [code]; matching ignores pair order.
  final String? secondCode;
  final bool control;
  final bool alt;
  final bool shift;
  final bool meta;
  final bool repeat;
  final bool composing;
  final bool defaultPrevented;
}

/// Read-only input action contributed while its owning feature is mounted.
class ShortcutFixedCommand {
  const ShortcutFixedCommand({
    required this.id,
    required this.label,
    required this.keys,
    required this.bindings,
    required this.group,
  });

  final String id;
  final String Function() label;
  final List<String> keys;

  /// One or more physical combinations reserved by this action.
  final List<ShortcutBinding> bindings;
  final ShortcutGroup group;
}

/// Reference groups.
enum ShortcutGroup { application, input, menus, approval }

/// Localized fixed-action row; its key sequence is not an editable binding.
class ShortcutFixedCatalogEntry {
  const ShortcutFixedCatalogEntry({
    required this.id,
    required this.label,
    required this.keys,
    required this.bindings,
    required this.group,
  });

  final String id;
  final String label;
  final List<String> keys;
  final List<NormalizedBinding> bindings;
  final ShortcutGroup group;
}

/// Dispatch consumption is independent of later business-operation success.
sealed class ShortcutDispatch {
  const ShortcutDispatch();
}

class DispatchHandled extends ShortcutDispatch {
  const DispatchHandled(this.commandId);

  final String commandId;
}

class DispatchBlocked extends ShortcutDispatch {
  const DispatchBlocked(this.commandId, this.reason);

  final String commandId;
  final String reason;
}

class DispatchPass extends ShortcutDispatch {
  const DispatchPass();
}

class _State {
  const _State(this.catalog, this.config);

  final List<ShortcutCatalogEntry> catalog;
  final ShortcutConfigSnapshot config;
}

/// Application command registry.
class ShortcutRegistry {
  ShortcutRegistry(
    this.runtime,
    this.platform, [
    ShortcutConfigSnapshot? config,
  ]) : _state = SnapshotStore(
         _State(
           const [],
           config ??
               initialShortcutConfig().copyWith(
                 status: ShortcutConfigStatus.ready,
               ),
         ),
       );

  final ShortcutRuntime runtime;
  final ShortcutPlatform platform;
  final Map<String, ShortcutCommand> _commands = {};
  final Map<String, ShortcutFixedCommand> _fixedCommands = {};
  final Map<String, ShortcutCommand> _conflicts = {};
  final Map<String, ShortcutCommand> _bindings = {};
  final SnapshotStore<_State> _state;

  /// Fixed local operations whose owning features are mounted.
  final SnapshotStore<List<ShortcutFixedCatalogEntry>> fixedCatalog =
      SnapshotStore(const []);

  /// Effective localized rows derived from the accepted configuration.
  List<ShortcutCatalogEntry> get catalog => _state.value.catalog;

  /// Accepted preferences and visible read diagnostics.
  ShortcutConfigSnapshot get config => _state.value.config;

  /// Subscribe to catalog and configuration changes (one notification per
  /// change publishes both). Returns the disposer.
  void Function() subscribe(void Function() listener) =>
      _state.subscribe(listener);

  /// The catalog row of command [id], if registered.
  ShortcutCatalogEntry? entry(String id) {
    for (final row in catalog) {
      if (row.id == id) return row;
    }
    return null;
  }

  /// The serializable active catalog for storage validation: definitions
  /// without callbacks or localized labels.
  List<ShortcutDefinition> definitions() => [
    for (final c in _commands.values)
      ShortcutDefinition(id: c.id, defaults: c.defaults),
    for (final f in _fixedCommands.values)
      ShortcutDefinition(id: f.id, defaults: const {}, fixed: f.bindings),
  ];

  /// Register a read-only input action whose keys cannot be assigned to
  /// editable commands. Returns an idempotent disposer.
  void Function() registerFixed(ShortcutFixedCommand command) {
    if (_fixedCommands.containsKey(command.id) ||
        _commands.containsKey(command.id)) {
      throw StateError('Duplicate shortcut command: ${command.id}');
    }
    for (final binding in command.bindings) {
      normalizeBinding(binding, platform);
    }
    _fixedCommands[command.id] = command;
    refreshLabels();
    return () {
      if (!identical(_fixedCommands[command.id], command)) return;
      _fixedCommands.remove(command.id);
      refreshLabels();
    };
  }

  void _refreshFixedLabels() {
    fixedCatalog.set([
      for (final c in _fixedCommands.values)
        ShortcutFixedCatalogEntry(
          id: c.id,
          label: c.label(),
          keys: c.keys,
          group: c.group,
          bindings: [for (final b in c.bindings) normalizeBinding(b, platform)],
        ),
    ]);
  }

  /// Publish accepted preferences and all derived labels atomically.
  void configure(ShortcutConfigSnapshot next) {
    final current = config;
    if (next.revision == current.revision &&
        next.status == current.status &&
        next.error == current.error) {
      return;
    }
    refreshLabels(next);
  }

  /// Register atomically after checking defaults for all supported platforms
  /// and shells. Returns an idempotent disposer removing both matching and
  /// catalog entries.
  void Function() register(ShortcutCommand command) {
    if (_commands.containsKey(command.id) ||
        _fixedCommands.containsKey(command.id)) {
      throw StateError('Duplicate shortcut command: ${command.id}');
    }
    for (final rt in ShortcutRuntime.values) {
      for (final pf in ShortcutPlatform.values) {
        final candidate = resolveShortcutDefault(
          ShortcutDefinition(id: command.id, defaults: command.defaults),
          rt,
          pf,
        );
        if (candidate == null) continue;
        final binding = normalizeBinding(candidate, pf);
        if (rt == ShortcutRuntime.web && !isWebBindingAllowed(binding, pf)) {
          throw StateError('Unsupported Web shortcut: ${command.id}');
        }
        if (bindingIssue(binding, rt, pf) != null) {
          throw StateError('Reserved shortcut default: ${command.id}');
        }
        for (final existing in _commands.values) {
          final other = resolveShortcutDefault(
            ShortcutDefinition(id: existing.id, defaults: existing.defaults),
            rt,
            pf,
          );
          if (other != null &&
              overlappingBindings(binding, normalizeBinding(other, pf))) {
            throw StateError(
              'Conflicting shortcut defaults: ${command.id} and ${existing.id} (${rt.name}:${pf.name})',
            );
          }
        }
      }
    }
    _commands[command.id] = command;
    refreshLabels();
    return () {
      if (!identical(_commands[command.id], command)) return;
      _commands.remove(command.id);
      refreshLabels();
    };
  }

  /// Recompute effective bindings when preferences, commands, or locale change.
  void refreshLabels([ShortcutConfigSnapshot? configuration]) {
    final cfg = configuration ?? config;
    _bindings.clear();
    _conflicts.clear();
    final rows = effectiveShortcuts(
      definitions(),
      cfg.document,
      runtime,
      platform,
    );
    final catalog = <ShortcutCatalogEntry>[];
    for (final row in rows) {
      final command = _commands[row.id]!;
      final enabled =
          cfg.status != ShortcutConfigStatus.loading &&
          row.issue == null &&
          row.conflicts.isEmpty;
      if (enabled && row.binding != null) {
        _bindings[bindingKey(row.binding!)] = command;
      }
      if (cfg.status != ShortcutConfigStatus.loading &&
          row.issue == null &&
          row.conflicts.isNotEmpty &&
          row.binding != null) {
        _conflicts[bindingKey(row.binding!)] = command;
      }
      final presented = presentBinding(row.binding, platform);
      catalog.add(
        ShortcutCatalogEntry(
          id: row.id,
          label: command.label(),
          aliases: command.aliases,
          keys: presented.keys,
          aria: enabled ? presented.aria : null,
          binding: row.binding,
          modified: row.modified,
          conflicts: row.conflicts,
          issue: row.issue,
        ),
      );
    }
    _state.set(_State(catalog, cfg));
    _refreshFixedLabels();
  }

  /// Invoke a native menu selection independently of its optional key binding.
  void invoke(String id, ShortcutContext context) {
    final command = _commands[id];
    if (command == null ||
        (context.modal != null && !command.modals.contains(context.modal))) {
      return;
    }
    final result = command.resolve(context.withSource(ShortcutSource.menu));
    if (result is ShortcutHandled) result.run();
  }

  bool get _priority =>
      runtime == ShortcutRuntime.desktop &&
      (platform == ShortcutPlatform.windows ||
          platform == ShortcutPlatform.macos);

  /// Windows/macOS desktop bindings override local regions and modal controls
  /// independently of their configuration source. [consume] is the adapter's
  /// preventDefault, called before business execution.
  ShortcutDispatch dispatch(
    ShortcutGesture gesture,
    ShortcutContext context,
    void Function() consume,
  ) {
    if (gesture.defaultPrevented || gesture.composing) {
      return const DispatchPass();
    }
    final modifiers = [
      if (gesture.control) ShortcutModifier.control,
      if (gesture.alt) ShortcutModifier.alt,
      if (gesture.shift) ShortcutModifier.shift,
      if (gesture.meta) ShortcutModifier.meta,
    ];
    final pairKey = bindingKey(
      NormalizedBinding(gesture.code, modifiers, gesture.secondCode),
    );
    final key =
        _bindings.containsKey(pairKey) || _conflicts.containsKey(pairKey)
        ? pairKey
        : bindingKey(NormalizedBinding(gesture.code, modifiers));
    final command = _bindings[key] ?? _conflicts[key];
    final priority = _priority;
    if (command == null ||
        (!priority && !command.regions.contains(context.region))) {
      return const DispatchPass();
    }
    if (!priority &&
        context.region == ShortcutRegion.terminal &&
        gesture.control &&
        !gesture.meta &&
        !gesture.alt &&
        !gesture.shift &&
        (gesture.code == 'KeyW' || gesture.code == 'KeyR')) {
      return const DispatchPass();
    }
    if (!_bindings.containsKey(key)) {
      consume();
      return DispatchBlocked(command.id, 'conflict');
    }
    if (!priority &&
        context.modal != null &&
        !command.modals.contains(context.modal)) {
      consume();
      return DispatchBlocked(command.id, 'modal');
    }
    final resolution = command.resolve(context);
    switch (resolution) {
      case ShortcutPass():
        return const DispatchPass();
      case ShortcutBlocked():
        consume();
        return DispatchBlocked(command.id, resolution.reason);
      case ShortcutHandled():
        consume();
        if (!gesture.repeat) resolution.run();
        return DispatchHandled(command.id);
    }
  }

  /// Describe a candidate using the device's physical-key and reservation
  /// rules; invalid codes throw. Canonical binding, visible keys, rejection
  /// reason, and overlapping editable/fixed command ids.
  ({
    NormalizedBinding? binding,
    List<String> keys,
    BindingIssue? issue,
    List<String> conflicts,
  })
  describeBinding(ShortcutBinding? binding) {
    if (binding == null) {
      return (binding: null, keys: const [], issue: null, conflicts: const []);
    }
    final normalized = normalizeBinding(binding, platform);
    final conflicts = <String>{};
    for (final row in catalog) {
      final b = row.binding;
      if (b != null && overlappingBindings(b, normalized)) {
        conflicts.add(row.id);
      }
    }
    for (final row in fixedCatalog.value) {
      if (row.bindings.any((b) => overlappingBindings(b, normalized))) {
        conflicts.add(row.id);
      }
    }
    return (
      binding: normalized,
      keys: presentBinding(normalized, platform).keys,
      issue: bindingIssue(normalized, runtime, platform),
      conflicts: conflicts.toList(),
    );
  }
}
