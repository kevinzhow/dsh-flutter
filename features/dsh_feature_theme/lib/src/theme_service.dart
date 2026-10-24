import 'dart:async';

import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_theme/dsh_theme.dart';

/// The `ui-theme` settings namespace on the host wire.
const String themeSettingsNamespace = 'ui-theme';

/// Field carrying the selected preference.
const String themePreferenceField = 'preference';

/// Owner of the live theme settings (dsh `ThemeRuntime`, the persistence half:
/// the browser-only parts, the `prefers-color-scheme` listener, token override
/// layers and the desktop font-size keys, have no counterpart here).
///
/// A change shows at once and is written through the shared `ui-theme` form,
/// so rapid changes serialize in gesture order with namespace revisions and a
/// rejected latest write reloads the durable values. While one of its own
/// writes is pending, the service ignores refetched sections, so an echo of an
/// earlier write cannot revert a later change; it adopts the durable section
/// once the writes settle.
class ThemeSettingsService {
  /// [host] is the shared form of the `ui-theme` entry; [initial] the values
  /// shown until the host answers (the last ones the device saw).
  ThemeSettingsService({required ConfigForm host, ThemeSettings? initial})
    : _host = host,
      settings = Observable(initial ?? ThemeSettings()) {
    _unsubscribe = host.subscribe(_adopt);
    _adopt();
  }

  final ConfigForm _host;
  late final void Function() _unsubscribe;
  int _pendingWrites = 0;
  bool _disposed = false;

  /// The persisted preference, sizes and font lists as they stand now.
  final Observable<ThemeSettings> settings;

  ThemeSettings get current => settings.value;

  /// Whether the host document accepts writes (the controls disable if not).
  bool get writable => _host.snapshot.writable;

  /// Whether the host serves the namespace at all.
  bool get available => _host.snapshot.status != ConfigFormStatus.unavailable;

  /// Switch the colour scheme preference.
  void setPreference(ThemePreference preference) {
    if (current.preference == preference) return;
    _publish(current.copyWith(preference: preference));
    _write(() => _host.set(themePreferenceField, preference.name));
  }

  /// Change one role's font size. A value outside the role's range throws, as
  /// dsh's `setFontSize` does.
  void setFontSize(FontRole role, int px) {
    final spec = fontSizeSpecs[role]!;
    if (!ThemeSettings.isValidFontSize(role, px)) {
      throw RangeError(
        '${role.name} font size $px is outside ${spec.min}..${spec.max}',
      );
    }
    if (current.fontSizes[role] == px) return;
    _publish(switch (role) {
      FontRole.text => current.copyWith(fontSize: px),
      FontRole.code => current.copyWith(codeFontSize: px),
      FontRole.terminal => current.copyWith(terminalFontSize: px),
    });
    _write(() => _host.set(spec.field, px));
  }

  /// Change one role's font list: normalized, written when it differs. A value
  /// without names restores the built-in stack.
  void setFontFamily(FontRole role, String value) {
    final list = normalizeFontFamily(value);
    if (current.fontFamilies[role] == list) return;
    _publish(switch (role) {
      FontRole.text => current.copyWith(textFontFamily: list),
      FontRole.code => current.copyWith(codeFontFamily: list),
      FontRole.terminal => current.copyWith(terminalFontFamily: list),
    });
    _write(() => _host.set(fontFamilyFields[role]!, list));
  }

  /// Queue one write, then adopt the durable section once no own write remains.
  void _write(Future<bool> Function() operation) {
    _pendingWrites += 1;
    unawaited(
      operation().then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        _pendingWrites -= 1;
        _adopt();
      }),
    );
  }

  /// Adopt the form's accepted durable section without writing it back.
  void _adopt() {
    if (_disposed || _pendingWrites > 0) return;
    final section = _host.snapshot.value;
    if (section == null) return;
    final ThemeSettings durable;
    try {
      durable = ThemeSettings.fromJson(section);
    } on ThemeException {
      return;
    }
    if (durable == current) return;
    _publish(durable);
  }

  void _publish(ThemeSettings next) => settings.set(next);

  Future<void> dispose() async {
    _disposed = true;
    _unsubscribe();
    await settings.dispose();
  }
}
