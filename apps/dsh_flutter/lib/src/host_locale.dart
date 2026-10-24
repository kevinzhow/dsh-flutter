import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';

/// The `locale` settings namespace on the host wire (dsh `client/locale`).
const String localeSettingsNamespace = 'locale';

/// The interface language, shared with the host's settings document (dsh
/// `LocaleRuntime`, the persistence half): an explicit `preference` in the
/// `locale` namespace wins, absence follows the device. A choice shows at once
/// and is written through the shared form; the durable value is adopted once
/// the app's own writes settle, as the theme service does.
class HostLocale {
  HostLocale({
    required ConfigForm host,
    required DshLocale initial,
    required DshLocale deviceLocale,
    required void Function(DshLocale locale) onChange,
  }) : _host = host,
       _device = deviceLocale,
       _onChange = onChange,
       _current = initial {
    _unsubscribe = host.subscribe(_adopt);
    _adopt();
  }

  final ConfigForm _host;
  final DshLocale _device;
  final void Function(DshLocale) _onChange;
  DshLocale _current;
  int _pending = 0;
  late final void Function() _unsubscribe;

  DshLocale get current => _current;

  /// Whether the host can store the choice.
  bool get writable => _host.snapshot.writable;

  /// Whether the host serves the namespace.
  bool get available => _host.snapshot.status != ConfigFormStatus.unavailable;

  void set(DshLocale locale) {
    if (_current == locale) return;
    _current = locale;
    _onChange(locale);
    _pending += 1;
    unawaited(
      _host
          .set('preference', locale.name)
          .then<void>((_) {}, onError: (Object _) {})
          .whenComplete(() {
            _pending -= 1;
            _adopt();
          }),
    );
  }

  void _adopt() {
    if (_pending > 0) return;
    final section = _host.snapshot.value;
    if (section == null) return;
    final preference = section['preference'];
    final DshLocale next = preference is String && preference.isNotEmpty
        ? DshLocale.fromTag(preference)
        : _device;
    if (next == _current) return;
    _current = next;
    _onChange(next);
  }

  void dispose() => _unsubscribe();
}
