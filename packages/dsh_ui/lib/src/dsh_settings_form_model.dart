/// The staged form model behind a plugin's settings page: a port of dsh's
/// `SettingsFormModel` (ui-primitives `settings-form/form-model.ts`), pure Dart.
///
/// A card stages what the user types and writes it only when they save. Each
/// settings write is a durable, revision-fenced document mutation, so a control
/// that committed as it settled turned one edit into a write the user never
/// asked for and could not preview; staged text makes what is on screen exactly
/// what a save would store.
///
/// A field shows its effective value (the user layer over the composition
/// layer over the schema default) and whether the user layer carries it. That
/// presence, not a value comparison, is what marks a field overridden: an
/// override equal to the composition default is still an override.
///
/// The model knows its entry only through [SettingsFormScope], so this library
/// imports neither the client nor the models layer; the app adapts the shared
/// configuration form to the scope. `tool/vectors` replays scripted scopes and
/// edits through dsh's TypeScript model and this one.
library;

import 'dart:async';

/// Whether the Host serves the entry to this client.
enum SettingsScopeStatus { loading, ready, unavailable }

/// What the model reads of one Host entry's form.
class SettingsFormScopeSnapshot {
  const SettingsFormScopeSnapshot({
    this.status = SettingsScopeStatus.loading,
    this.value,
    this.base,
    this.user,
    this.writable = false,
    this.revision,
  });

  /// `ready` while the Host serves the entry to this client; the form renders
  /// nothing otherwise.
  final SettingsScopeStatus status;

  /// Last accepted schema-resolved section; null before the first acceptance.
  final Object? value;

  /// Composition layer the value resolves over: what a field reverts to once
  /// cleared.
  final Object? base;

  /// Raw user layer as stored; a field's PRESENCE here is what marks it
  /// overridden.
  final Object? user;

  /// Whether the Host document accepts writes.
  final bool writable;

  /// Revision the snapshot was read at; a save fences its mutation with the
  /// revision its drafts started from.
  final int? revision;
}

/// One path edit a save sends, as the shared configuration form's `mutate`
/// accepts it.
sealed class SettingsFormPathOp {
  const SettingsFormPathOp(this.path);
  final List<String> path;
}

/// Write [value] at the path.
final class SettingsFormSetOp extends SettingsFormPathOp {
  const SettingsFormSetOp(super.path, this.value);
  final Object? value;
}

/// Remove the value at the path, so the field re-inherits the composition
/// layer.
final class SettingsFormUnsetOp extends SettingsFormPathOp {
  const SettingsFormUnsetOp(super.path);
}

/// The entry form the model stages over: the reads and the atomic write of the
/// form the settings domain shares per Host entry.
abstract interface class SettingsFormScope {
  /// The current sync snapshot.
  SettingsFormScopeSnapshot get snapshot;

  /// Observe snapshot replacements; returns the disposer.
  void Function() subscribe(void Function() listener);

  /// Apply ordered field edits in one revision-fenced write. [expectedRevision]
  /// is the revision the drafts were staged against, when known. Resolves true
  /// for Host acceptance, false for refusal, after any recovery read.
  Future<bool> mutate(List<SettingsFormPathOp> ops, {int? expectedRevision});
}

/// The write one field's staged text performs when the card is saved.
sealed class SettingsFieldWrite {
  const SettingsFieldWrite();
}

/// Store [value] in the field.
final class SettingsFieldSet extends SettingsFieldWrite {
  const SettingsFieldSet(this.value);
  final Object? value;
}

/// Clear the field.
final class SettingsFieldClear extends SettingsFieldWrite {
  const SettingsFieldClear();
}

/// How one section field converts between its stored value and its draft text.
class SettingsFieldSpec {
  const SettingsFieldSpec({
    required this.field,
    required this.format,
    required this.parse,
  });

  /// Field name inside the namespace section.
  final String field;

  /// Render a stored value as draft text; the empty string when the section
  /// carries none.
  final String Function(Object? value) format;

  /// The write this draft text stages, or null when the text is not a value
  /// this field accepts, which blocks the save rather than discarding it.
  final SettingsFieldWrite? Function(String text) parse;
}

/// A control whose value is written outside the settings section. A credential
/// literal never rides a response, so its draft has nothing to seed from: it is
/// blank until typed, and a blank draft writes nothing.
class SettingsSecretSpec {
  const SettingsSecretSpec({required this.field, required this.write});

  /// Field name addressing this control inside the card's form.
  final String field;

  /// Write the staged text; resolves to whether the Host accepted it.
  final Future<bool> Function(String text) write;
}

/// One field as a card's control renders it.
class SettingsFieldState {
  const SettingsFieldState({
    required this.text,
    required this.overridden,
    required this.invalid,
  });

  /// Draft text the control renders.
  final String text;

  /// Whether saving would leave a user-layer entry for this field. A staged
  /// edit answers for itself, so the badge previews the save rather than
  /// reporting a state the pending edit already contradicts.
  final bool overridden;

  /// Whether the draft is not a value this field accepts, which blocks saving.
  final bool invalid;
}

/// Form state every plugin card shares.
class SettingsFormShell {
  const SettingsFormShell({
    required this.available,
    required this.writable,
    required this.dirty,
    required this.invalid,
    required this.saving,
    required this.failed,
  });

  /// False while the namespace is not served to this client; the card renders
  /// nothing.
  final bool available;

  /// Whether the Host document accepts writes.
  final bool writable;

  /// Whether the form holds edits that a save would write.
  final bool dirty;

  /// Whether any staged draft is invalid, which blocks the save.
  final bool invalid;

  /// Whether a save is crossing the wire.
  final bool saving;

  /// Whether the last save did not land as staged; cleared by the next edit or
  /// save.
  final bool failed;
}

/// The write actions every plugin card's slot entry injects.
class SettingsFormActions {
  const SettingsFormActions({
    required this.edit,
    required this.resetField,
    required this.save,
    required this.discard,
  });

  /// Stage draft text for one field.
  final void Function(String field, String text) edit;

  /// Stage a clear, so saving lets the field re-inherit the composition layer.
  final void Function(String field) resetField;

  /// Write every staged edit, then re-seed from what the Host accepted.
  final void Function() save;

  /// Drop every staged edit.
  final void Function() discard;
}

/// A bare observable holding the latest projection a card renders (dsh's
/// snapshot store, without the React-facing selector machinery).
class SettingsFormStore<S> {
  SettingsFormStore(this._value);

  S _value;
  final List<void Function()> _listeners = [];

  /// The current projection.
  S get value => _value;

  /// Replace the projection and notify.
  void set(S next) {
    _value = next;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  /// Observe replacements; returns the disposer.
  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

/// A whole-number field. An empty draft clears the field; any other draft that
/// is not a finite number blocks the save.
SettingsFieldSpec settingsNumberField(String field) => SettingsFieldSpec(
  field: field,
  // A section that carries no number for this field renders empty rather than
  // as a value nobody chose.
  format: (value) => value is num ? _jsNumberString(value) : '',
  parse: (text) {
    final trimmed = _jsTrim(text);
    if (trimmed.isEmpty) return const SettingsFieldClear();
    final parsed = _jsNumber(trimmed);
    return parsed == null ? null : SettingsFieldSet(parsed);
  },
);

/// A free-text field. An empty draft clears the field, so emptying the control
/// and saving is the same gesture as resetting it.
SettingsFieldSpec settingsTextField(String field) => SettingsFieldSpec(
  field: field,
  format: (value) => value is String ? value : '',
  parse: (text) {
    final trimmed = _jsTrim(text);
    return trimmed.isEmpty
        ? const SettingsFieldClear()
        : SettingsFieldSet(trimmed);
  },
);

/// One field's staged edit.
class _StagedEdit {
  const _StagedEdit(this.text, {required this.clear});

  /// Draft text the control renders.
  final String text;

  /// True when this edit clears the field whatever text it shows.
  final bool clear;
}

/// One staged edit resolved into the write a save performs.
class _PlannedWrite {
  const _PlannedWrite(this.field, {this.run, this.op});

  final String field;

  /// Performs the write and reports whether the Host holds the staged value
  /// afterwards.
  final Future<bool> Function()? run;
  final SettingsFormPathOp? op;

  /// An entry whose draft is not a value its field accepts carries no write.
  bool get unwritable => run == null && op == null;
}

/// Stages one card's edits over one settings namespace and writes them on
/// save.
///
/// The form publishes through [bind]'s store because slot components read
/// through a snapshot selector, while both the scope and the local drafts
/// change underneath; every projection is rebuilt from the two together.
class SettingsFormModel {
  /// [scope] is the shared configuration form for this card's namespace,
  /// [specs] the section fields this card edits, [secrets] the card's
  /// write-only controls, written outside the section.
  SettingsFormModel(
    this._scope,
    List<SettingsFieldSpec> specs, [
    List<SettingsSecretSpec> secrets = const [],
  ]) : _specs = {for (final spec in specs) spec.field: spec},
       _secretSpecs = {for (final spec in secrets) spec.field: spec} {
    _unsubscribe = _scope.subscribe(_publish);
  }

  final SettingsFormScope _scope;
  final Map<String, SettingsFieldSpec> _specs;
  final Map<String, SettingsSecretSpec> _secretSpecs;
  final Map<String, _StagedEdit> _staged = {};
  final List<void Function()> _listeners = [];
  SettingsFormScopeSnapshot? _baseline;
  late final void Function() _unsubscribe;
  bool _saving = false;
  bool _failed = false;

  /// Publish a projection of this form, rebuilt whenever the scope or a draft
  /// changes. [project] builds the card's state from the form's current reads.
  SettingsFormStore<S> bind<S>(S Function() project) {
    final store = SettingsFormStore<S>(project());
    _listeners.add(() => store.set(project()));
    return store;
  }

  /// The card-level state: what the Host serves, and what a save would do.
  SettingsFormShell shell() {
    final snapshot = _scope.snapshot;
    final plan = _plan();
    return SettingsFormShell(
      available: snapshot.status == SettingsScopeStatus.ready,
      writable: snapshot.writable,
      dirty: plan.isNotEmpty,
      invalid: plan.any((item) => item.unwritable),
      saving: _saving,
      failed: _failed,
    );
  }

  /// One control's state: the draft text, whether a save would leave an
  /// override, and whether it is invalid. [field] names a section field or a
  /// write-only control.
  SettingsFieldState field(String field) {
    final staged = _staged[field];
    if (_secretSpecs.containsKey(field)) {
      return SettingsFieldState(
        text: staged?.text ?? '',
        overridden: false,
        invalid: false,
      );
    }
    final spec = _spec(field);
    if (staged == null) {
      return SettingsFieldState(
        text: spec.format(_sectionValue(field)),
        overridden: _stored(field),
        invalid: false,
      );
    }
    final write = staged.clear
        ? const SettingsFieldClear()
        : spec.parse(staged.text);
    return SettingsFieldState(
      text: staged.text,
      overridden: write is SettingsFieldSet,
      invalid: write == null,
    );
  }

  /// The edit, reset, save and discard actions bound to this form.
  SettingsFormActions actions() => SettingsFormActions(
    edit: (field, text) => _stage(field, _StagedEdit(text, clear: false)),
    resetField: (field) => _stage(
      field,
      _StagedEdit(_spec(field).format(_baseValue(field)), clear: true),
    ),
    save: () => unawaited(save()),
    discard: () {
      if (_staged.isEmpty && !_failed) return;
      _staged.clear();
      _baseline = null;
      _failed = false;
      _publish();
    },
  );

  /// Write every staged edit, then re-seed from what the Host accepted.
  ///
  /// The Host is the only authority on whether a value was accepted (its
  /// validators own the constraints no schema can express), so the outcome is
  /// read back from the section rather than predicted here. A save that did not
  /// land keeps its drafts, so the user can correct them instead of retyping.
  Future<void> save() async {
    final plan = _plan();
    if (plan.isEmpty ||
        _saving ||
        !_scope.snapshot.writable ||
        plan.any((item) => item.unwritable)) {
      return;
    }
    _saving = true;
    _failed = false;
    _publish();
    try {
      final ops = [
        for (final item in plan)
          if (item.op != null) item.op!,
      ];
      var landed =
          ops.isEmpty ||
          await _scope.mutate(ops, expectedRevision: _baseline?.revision);
      if (!landed) {
        _failed = true;
        return;
      }
      for (final item in plan) {
        final run = item.run;
        if (run != null) landed = await run() && landed;
      }
      if (landed) {
        _staged.clear();
        _baseline = null;
      }
      _failed = !landed;
    } on Object {
      _failed = true;
    } finally {
      _saving = false;
      _publish();
    }
  }

  /// Release the form's accepted-value subscription.
  void dispose() {
    _unsubscribe();
    _listeners.clear();
  }

  /// Every staged edit a save would write. An entry whose draft is not a value
  /// its field accepts carries no write: the form is still dirty, and the save
  /// refuses rather than dropping the edit. In the order the fields were
  /// staged.
  List<_PlannedWrite> _plan() {
    final plan = <_PlannedWrite>[];
    for (final entry in _staged.entries) {
      final field = entry.key;
      final staged = entry.value;
      final secret = _secretSpecs[field];
      if (secret != null) {
        final value = _jsTrim(staged.text);
        if (value.isNotEmpty) {
          plan.add(_PlannedWrite(field, run: () => secret.write(value)));
        }
        continue;
      }
      final spec = _spec(field);
      if (staged.clear) {
        if (_stored(field)) {
          plan.add(_PlannedWrite(field, op: SettingsFormUnsetOp([field])));
        }
        continue;
      }
      if (staged.text == spec.format(_sectionValue(field))) continue;
      final write = spec.parse(staged.text);
      plan.add(switch (write) {
        null => _PlannedWrite(field),
        SettingsFieldClear() => _PlannedWrite(
          field,
          op: SettingsFormUnsetOp([field]),
        ),
        SettingsFieldSet(:final value) => _PlannedWrite(
          field,
          op: SettingsFormSetOp([field], value),
        ),
      });
    }
    return plan;
  }

  void _stage(String field, _StagedEdit edit) {
    _baseline ??= _scope.snapshot;
    _staged[field] = edit;
    _failed = false;
    _publish();
  }

  SettingsFieldSpec _spec(String field) {
    final spec = _specs[field];
    // Every call site names a field this card declared; a missing one is a
    // wiring mistake that must not degrade into a silently inert control.
    if (spec == null) throw StateError('plugin card has no field $field');
    return spec;
  }

  Object? _sectionValue(String field) {
    final value = _scope.snapshot.value;
    return value is Map ? value[field] : null;
  }

  Object? _baseValue(String field) {
    final base = _scope.snapshot.base;
    return base is Map ? base[field] : null;
  }

  bool _stored(String field) {
    final user = _scope.snapshot.user;
    return user is Map && user.containsKey(field);
  }

  void _publish() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}

// ---- JavaScript string and number semantics the field specs rely on --------

/// `String.prototype.trim`: ECMAScript white space and line terminators (U+0085
/// is not among them, U+FEFF is).
String _jsTrim(String text) {
  var start = 0;
  var end = text.length;
  while (start < end && _isJsSpace(text.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _isJsSpace(text.codeUnitAt(end - 1))) {
    end--;
  }
  return text.substring(start, end);
}

bool _isJsSpace(int unit) =>
    (unit >= 0x09 && unit <= 0x0d) ||
    unit == 0x20 ||
    unit == 0xa0 ||
    unit == 0x1680 ||
    (unit >= 0x2000 && unit <= 0x200a) ||
    unit == 0x2028 ||
    unit == 0x2029 ||
    unit == 0x202f ||
    unit == 0x205f ||
    unit == 0x3000 ||
    unit == 0xfeff;

final RegExp _decimalLiteral = RegExp(
  r'^([+-]?)(?:(\d+)\.?(\d*)|\.(\d+))(?:[eE]([+-]?\d+))?$',
);
final RegExp _radixLiteral = RegExp(
  r'^0(?:([xX])([0-9a-fA-F]+)|([oO])([0-7]+)|([bB])([01]+))$',
);

/// `Number(text)` for a trimmed, non-empty [text], or null where JavaScript
/// answers NaN or an infinity (neither is a value the number field accepts).
/// A whole result inside the exact range comes back as an `int`.
num? _jsNumber(String text) {
  double? value;
  final radix = _radixLiteral.firstMatch(text);
  if (radix != null) {
    final digits = radix[2] ?? radix[4] ?? radix[6]!;
    final base = radix[1] != null ? 16 : (radix[3] != null ? 8 : 2);
    value = BigInt.parse(digits, radix: base).toDouble();
  } else {
    final decimal = _decimalLiteral.firstMatch(text);
    if (decimal == null) return null;
    final whole = decimal[2] ?? '0';
    final fraction = decimal[3] ?? decimal[4] ?? '';
    final exponent = decimal[5] ?? '0';
    value = double.parse(
      '${decimal[1]}$whole.${fraction.isEmpty ? '0' : fraction}e$exponent',
    );
  }
  if (!value.isFinite) return null;
  if (value == 0 && value.isNegative) return value;
  if (value == value.truncateToDouble() && value.abs() < 9007199254740992) {
    return value.toInt();
  }
  return value;
}

/// `String(number)`: shortest round-trip digits, positional notation for
/// exponents in [-7, 21), `e+N` otherwise, `0` for -0.
String _jsNumberString(num n) {
  if (n is int && n.abs() < 9007199254740992) return '$n';
  final d = n.toDouble();
  if (d.isNaN) return 'NaN';
  if (d.isInfinite) return d.isNegative ? '-Infinity' : 'Infinity';
  if (d == 0) return '0';
  final sign = d < 0 ? '-' : '';
  final parts = d.abs().toStringAsExponential().split('e');
  final digits = parts[0].replaceAll('.', '');
  final point = int.parse(parts[1]) + 1;
  final k = digits.length;
  if (k <= point && point <= 21) return '$sign$digits${'0' * (point - k)}';
  if (0 < point && point <= 21) {
    return '$sign${digits.substring(0, point)}.${digits.substring(point)}';
  }
  if (-6 < point && point <= 0) return '${sign}0.${'0' * -point}$digits';
  final exponent = point - 1;
  final mantissa = k == 1 ? digits : '${digits[0]}.${digits.substring(1)}';
  return '$sign${mantissa}e${exponent < 0 ? '-' : '+'}${exponent.abs()}';
}
