/// The form frame and value field of a plugin's settings page: ports of dsh's
/// `SettingsForm` and `SettingsValueField` (ui-primitives `settings-form`).
///
/// Nothing here writes. A field reports what the user typed, and the form's
/// save is the single point where staged drafts become one settings mutation
/// (see `SettingsFormModel`).
library;

import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/services.dart' show LogicalKeyboardKey, TextInputAction;
import 'package:flutter/widgets.dart';

import 'dsh_button.dart';
import 'dsh_control_focus_modality.dart';
import 'dsh_corners.dart';
import 'dsh_pixel_snap.dart';
import 'dsh_settings.dart';
import 'dsh_settings_form_model.dart';
import 'dsh_snapped_box.dart';
import 'dsh_tag.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

/// The copy the form frame renders, from the owning plugin's dictionary (dsh
/// `SettingsFormLabels`).
class DshSettingsFormLabels {
  const DshSettingsFormLabels({
    required this.unavailable,
    required this.readOnly,
    required this.saveFailed,
    required this.save,
    required this.saving,
  });

  /// Shown in place of the controls while the namespace is not served.
  final String unavailable;

  /// Shown over the controls while the document is read-only.
  final String readOnly;

  /// Shown beside the save after a save the Host did not accept.
  final String saveFailed;

  /// The save control.
  final String save;

  /// The save control while a save is crossing the wire.
  final String saving;
}

/// One plugin's settings form as its page shows it (dsh `SettingsForm`): the
/// read-only notice when the deployment stores settings read-only, the
/// plugin's controls, and the save that writes every staged edit.
///
/// Only a save writes. Leaving the page drops every staged edit, so the form
/// calls [onDiscard] when it leaves the tree and offers no discard control. A
/// form whose namespace the Host stopped serving says so in place of its
/// controls rather than showing fields nothing would accept.
class DshSettingsForm extends StatefulWidget {
  const DshSettingsForm({
    super.key,
    required this.labels,
    required this.state,
    required this.onSave,
    required this.onDiscard,
    required this.children,
  });

  final DshSettingsFormLabels labels;

  /// Availability, writability, and what a save would do.
  final SettingsFormShell state;

  /// Write every staged edit.
  final VoidCallback onSave;

  /// Drop every staged edit; run when the form leaves the page.
  final VoidCallback onDiscard;

  /// The plugin's controls.
  final List<Widget> children;

  /// Key of the save button.
  static const Key saveKey = ValueKey<String>('settings-form-save');

  /// Key of the failed-save notice.
  static const Key failedKey = ValueKey<String>('settings-form-failed');

  /// Key of the read-only notice.
  static const Key readOnlyKey = ValueKey<String>('settings-form-read-only');

  /// Key of the unavailable notice.
  static const Key unavailableKey = ValueKey<String>(
    'settings-form-unavailable',
  );

  @override
  State<DshSettingsForm> createState() => _DshSettingsFormState();
}

class _DshSettingsFormState extends State<DshSettingsForm> {
  late VoidCallback _discard = widget.onDiscard;

  @override
  void didUpdateWidget(DshSettingsForm old) {
    super.didUpdateWidget(old);
    _discard = widget.onDiscard;
  }

  @override
  void dispose() {
    _discard();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final state = widget.state;
    final labels = widget.labels;
    final note = theme
        .textStyle('--dsw-font-xxs-12')
        .copyWith(color: theme.color('--dsw-alias-label-tertiary'));
    if (!state.available) {
      return Semantics(
        liveRegion: true,
        child: DshLineText(
          labels.unavailable,
          key: DshSettingsForm.unavailableKey,
          style: note,
        ),
      );
    }
    final blocked = !state.dirty || state.invalid || state.saving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!state.writable)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Semantics(
              liveRegion: true,
              child: DshLineText(
                labels.readOnly,
                key: DshSettingsForm.readOnlyKey,
                style: note,
              ),
            ),
          ),
        ...widget.children,
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (state.failed)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Semantics(
                      liveRegion: true,
                      child: DshLineText(
                        labels.saveFailed,
                        key: DshSettingsForm.failedKey,
                        style: note.copyWith(
                          color: theme.color('--dsw-alias-state-error-primary'),
                        ),
                      ),
                    ),
                  ),
                ),
              KeyedSubtree(
                key: DshSettingsForm.saveKey,
                child: DshButton(
                  variant: DshButtonVariant.primary,
                  onPressed: blocked ? null : widget.onSave,
                  child: DshChromeText(
                    state.saving ? labels.saving : labels.save,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Rules disclosed by the information button beside a field's label (dsh
/// `SettingsValueField` `help`).
class DshSettingsFieldHelp {
  const DshSettingsFieldHelp({required this.label, required this.content});

  /// The button's accessible name, and the disclosed region's.
  final String label;

  /// The disclosed rules.
  final Widget content;
}

/// A staged value field (dsh `SettingsValueField`): a label, the staged text,
/// an Overridden badge with its reset while saving would leave a user-layer
/// entry, and the hint, or the invalid message while the draft is not a value
/// the field accepts. [numeric] only hints the keypad: which drafts a field
/// accepts is decided by its spec, so the control never rewrites what the user
/// typed.
class DshSettingsValueField extends StatefulWidget {
  const DshSettingsValueField({
    super.key,
    required this.id,
    required this.label,
    required this.text,
    required this.overridden,
    required this.invalid,
    required this.overriddenLabel,
    required this.resetLabel,
    required this.invalidLabel,
    required this.disabled,
    required this.onEdit,
    required this.onReset,
    this.hint,
    this.help,
    this.numeric = false,
    this.placeholder,
    this.topDivider = false,
  });

  /// Stable id: the keys of the field's parts derive from it.
  final String id;
  final String label;

  /// One-line explanation under the control.
  final String? hint;

  /// Rules disclosed by the information button beside the label.
  final DshSettingsFieldHelp? help;

  /// Draft text the control shows.
  final String text;

  /// Whether saving would leave a user-layer entry for this field.
  final bool overridden;

  /// Whether the draft is not a value this field accepts.
  final bool invalid;

  final String overriddenLabel;
  final String resetLabel;

  /// Shown in place of the hint while the draft is invalid.
  final String invalidLabel;

  /// Disables the input and the reset (read-only document, or a save in
  /// flight).
  final bool disabled;
  final bool numeric;
  final String? placeholder;

  /// A hairline above the field: dsh draws it between sibling fields
  /// (`.field + .field`).
  final bool topDivider;

  /// Stage draft text.
  final ValueChanged<String> onEdit;

  /// Stage a clear, so the field re-inherits the composition layer.
  final VoidCallback onReset;

  /// Key of the text input of field [id].
  static Key inputKey(String id) => ValueKey<String>('$id-input');

  /// Key of the reset control of field [id].
  static Key resetKey(String id) => ValueKey<String>('$id-reset');

  /// Key of the Overridden badge of field [id].
  static Key badgeKey(String id) => ValueKey<String>('$id-overridden');

  /// Key of the information button of field [id].
  static Key helpKey(String id) => ValueKey<String>('$id-help');

  /// Keys of visible keyboard focus outlines on the field actions.
  static Key actionFocusRingKey(String id, String action) =>
      ValueKey<String>('$id-$action-focus-ring');

  /// Key of the hint or invalid message of field [id].
  static Key messageKey(String id) => ValueKey<String>('$id-message');

  @override
  State<DshSettingsValueField> createState() => _DshSettingsValueFieldState();
}

class _DshSettingsValueFieldState extends State<DshSettingsValueField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );
  final FocusNode _focus = FocusNode();
  bool _focused = false;
  bool _helpOpen = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      final focused = _focus.hasFocus;
      if (focused != _focused) setState(() => _focused = focused);
    });
  }

  @override
  void didUpdateWidget(DshSettingsValueField old) {
    super.didUpdateWidget(old);
    // A staged edit comes back as the same text; a reset or a re-seed after a
    // save is the only thing that changes it underneath the user.
    if (_controller.text != widget.text) {
      _controller.value = TextEditingValue(
        text: widget.text,
        selection: TextSelection.collapsed(offset: widget.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final labelStyle = theme
        .textStyle('--dsw-font-xs-13')
        .copyWith(color: theme.labelPrimary, fontWeight: FontWeight.w500);
    final small = theme.textStyle('--dsw-font-xxs-12');
    final tertiary = theme.color('--dsw-alias-label-tertiary');
    final id = widget.id;
    final hasMessage = widget.invalid || (widget.hint?.isNotEmpty ?? false);
    final help = widget.help;

    Widget badges() => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KeyedSubtree(
          key: DshSettingsValueField.badgeKey(id),
          child: DshTag.text(widget.overriddenLabel, tone: DshTagTone.neutral),
        ),
        const SizedBox(width: 8),
        _SettingsFieldAction(
          key: DshSettingsValueField.resetKey(id),
          label: widget.resetLabel,
          onPressed: widget.disabled ? null : widget.onReset,
          focusRingKey: DshSettingsValueField.actionFocusRingKey(id, 'reset'),
          // The visual button is 18px high in the source; keep its existing
          // 24px touch target without enlarging the keyboard outline.
          ringVerticalInset: 3,
          child: (hovered) => ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 24),
            child: Center(
              widthFactor: 1,
              child: DshLineText(
                widget.resetLabel,
                maxLines: 1,
                style: small.copyWith(
                  color: hovered && !widget.disabled
                      ? theme.labelPrimary
                      : theme.labelSecondary,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    Widget labelGroup() => Row(
      children: [
        Flexible(
          child: Semantics(
            label: widget.label,
            excludeSemantics: true,
            child: DshLineText(widget.label, style: labelStyle),
          ),
        ),
        if (help != null) ...[
          const SizedBox(width: 4),
          _SettingsFieldAction(
            key: DshSettingsValueField.helpKey(id),
            expanded: _helpOpen,
            label: help.label,
            onPressed: () => setState(() => _helpOpen = !_helpOpen),
            focusRingKey: DshSettingsValueField.actionFocusRingKey(id, 'help'),
            focusOffset: 1,
            radius: theme.radiusSm,
            // The source hover fill references --dsw-alias-bg-layer-4,
            // which the pinned theme does not define, so it paints no fill.
            child: (hovered) => SizedBox(
              width: 24,
              height: 24,
              child: Center(
                child: _InfoGlyph(
                  color: hovered || _helpOpen ? theme.labelSecondary : tertiary,
                ),
              ),
            ),
          ),
        ],
      ],
    );

    final head = LayoutBuilder(
      builder: (context, constraints) {
        // Phone width: the badge and reset go under the label instead of
        // squeezing it.
        if (constraints.maxWidth < dshSettingsRowWide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              labelGroup(),
              if (widget.overridden) ...[const SizedBox(height: 4), badges()],
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: labelGroup()),
            if (widget.overridden) badges(),
          ],
        );
      },
    );

    final enabled = !widget.disabled;
    final borderColor = widget.invalid
        ? theme.color('--dsw-alias-state-error-primary')
        : _focused
        ? theme.color('--dsw-alias-state-business-primary')
        : theme.color('--dsw-alias-border-l4');
    final inputStyle = theme
        .textStyle('--dsw-font-xs-13')
        .copyWith(color: enabled ? theme.labelPrimary : tertiary);
    final input = Semantics(
      label: widget.label,
      textField: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? _focus.requestFocus : null,
        child: DshContainer(
          height: 32 + 2 * dshHairlineOf(context),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: theme.cornerDecoration(
            theme.radiusMd,
            color: theme.color('--dsw-alias-bg-layer-3'),
            borderColor: borderColor,
            borderWidth: dshHairlineOf(context),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: EditableText(
              key: DshSettingsValueField.inputKey(id),
              controller: _controller,
              focusNode: _focus,
              readOnly: !enabled,
              maxLines: 1,
              style: inputStyle,
              cursorColor: theme.focusRingColor,
              backgroundCursorColor: theme.labelSecondary,
              selectionColor: theme.focusRingColor.withValues(alpha: 0.3),
              keyboardType: widget.numeric ? TextInputType.number : null,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: widget.onEdit,
              onSubmitted: (_) => _focus.unfocus(),
            ),
          ),
        ),
      ),
    );

    return DshDecoratedBox(
      decoration: BoxDecoration(
        border: widget.topDivider
            ? Border(
                top: BorderSide(
                  color: theme.color('--dsw-alias-border-l2'),
                  width: dshHairlineOf(context),
                ),
              )
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            head,
            const SizedBox(height: 6),
            input,
            if (hasMessage) ...[
              const SizedBox(height: 6),
              Semantics(
                liveRegion: widget.invalid,
                child: DshLineText(
                  widget.invalid ? widget.invalidLabel : widget.hint!,
                  key: DshSettingsValueField.messageKey(id),
                  style: small.copyWith(
                    color: widget.invalid
                        ? theme.color('--dsw-alias-state-error-primary')
                        : tertiary,
                  ),
                ),
              ),
            ],
            if (help != null && _helpOpen)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Semantics(
                  container: true,
                  label: help.label,
                  child: DefaultTextStyle.merge(
                    style: small.copyWith(color: theme.labelSecondary),
                    child: help.content,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Native equivalents of the source field's help and reset HTML buttons.
class _SettingsFieldAction extends StatefulWidget {
  const _SettingsFieldAction({
    super.key,
    required this.label,
    required this.onPressed,
    required this.focusRingKey,
    required this.child,
    this.expanded,
    this.focusOffset = 0,
    this.radius = 0,
    this.ringVerticalInset = 0,
  });

  final String label;
  final VoidCallback? onPressed;
  final Key focusRingKey;
  final Widget Function(bool hovered) child;
  final bool? expanded;
  final double focusOffset, radius, ringVerticalInset;

  @override
  State<_SettingsFieldAction> createState() => _SettingsFieldActionState();
}

class _SettingsFieldActionState extends State<_SettingsFieldAction> {
  final _focus = FocusNode(debugLabel: 'settings field action');
  bool _hovered = false, _focused = false, _focusVisible = false;

  @override
  void initState() {
    super.initState();
    DshControlFocusModality.instance.acquire(_modalityChanged);
  }

  void _modalityChanged() => _set(() {});
  void _set(VoidCallback change) {
    if (mounted) setState(change);
  }

  @override
  void dispose() {
    DshControlFocusModality.instance.release(_modalityChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final theme = context.dsh;
    final width = dshBorderWidthOf(context, theme.focusRingWidth);
    // The reset uses the browser's centred auto outline. The help button's
    // stylesheet instead specifies a one-pixel offset from its border.
    final reach = widget.focusOffset == 0
        ? width / 2
        : width + widget.focusOffset;
    return Semantics(
      button: true,
      enabled: enabled,
      focused: _focused,
      expanded: widget.expanded,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onPressed,
      onFocus: enabled ? _focus.requestFocus : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => _set(() => _hovered = true),
        onExit: (_) => _set(() => _hovered = false),
        child: FocusableActionDetector(
          enabled: enabled,
          focusNode: _focus,
          onFocusChange: (value) => _set(() => _focused = value),
          onShowFocusHighlight: (value) => _set(() => _focusVisible = value),
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed?.call();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: widget.onPressed,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                widget.child(_hovered),
                if (enabled &&
                    _focusVisible &&
                    _focus.hasPrimaryFocus &&
                    !DshControlFocusModality.instance.pointerOwnsFocus)
                  Positioned(
                    left: -reach,
                    top: -reach + widget.ringVerticalInset,
                    right: -reach,
                    bottom: -reach + widget.ringVerticalInset,
                    child: IgnorePointer(
                      child: DshDecoratedBox(
                        key: widget.focusRingKey,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            widget.radius + reach,
                          ),
                          border: Border.all(
                            color: theme.focusRingColor,
                            width: width,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 12px outlined circle with an "i": the information glyph of the help
/// button (dsh `IconInfoOutlineRegular`).
class _InfoGlyph extends StatelessWidget {
  const _InfoGlyph({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size.square(12), painter: _InfoPainter(color));
}

class _InfoPainter extends CustomPainter {
  _InfoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    final centre = size.center(Offset.zero);
    canvas.drawCircle(centre, size.width / 2 - 0.5, stroke);
    canvas.drawLine(
      Offset(centre.dx, centre.dy - 0.5),
      Offset(centre.dx, centre.dy + 2.5),
      stroke,
    );
    canvas.drawCircle(
      Offset(centre.dx, centre.dy - 2.5),
      0.6,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_InfoPainter old) => old.color != color;
}

/// Rebuilds [builder] with the latest projection of a [SettingsFormStore], as
/// dsh's slot components read their card state through a snapshot selector.
class DshSettingsFormStoreBuilder<S> extends StatefulWidget {
  const DshSettingsFormStoreBuilder({
    super.key,
    required this.store,
    required this.builder,
  });

  final SettingsFormStore<S> store;
  final Widget Function(BuildContext context, S state) builder;

  @override
  State<DshSettingsFormStoreBuilder<S>> createState() =>
      _DshSettingsFormStoreBuilderState<S>();
}

class _DshSettingsFormStoreBuilderState<S>
    extends State<DshSettingsFormStoreBuilder<S>> {
  void Function()? _off;

  @override
  void initState() {
    super.initState();
    _off = widget.store.subscribe(_changed);
  }

  @override
  void didUpdateWidget(DshSettingsFormStoreBuilder<S> old) {
    super.didUpdateWidget(old);
    if (!identical(old.store, widget.store)) {
      _off?.call();
      _off = widget.store.subscribe(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _off?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.store.value);
}
