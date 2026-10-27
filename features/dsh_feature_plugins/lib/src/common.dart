import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart'
    show TextField, InputDecoration, Material, MaterialType;
import 'package:flutter/widgets.dart';

String pluginText(Object? value, DshI18n i18n, [String fallback = '']) {
  if (value is String) return value;
  if (value is Map) {
    return pluginText(
      value[i18n.locale.name] ??
          value['en'] ??
          value['zh'] ??
          value.values.firstOrNull,
      i18n,
      fallback,
    );
  }
  return fallback;
}

Widget pluginHeading(BuildContext context, String text) => Text(
  text,
  style: context.dsh
      .textStyle('--dsw-font-l-20')
      .copyWith(color: context.dsh.labelPrimary),
);
Widget pluginStatus(BuildContext context, String text) => Text(
  text,
  style: context.dsh
      .textStyle('--dsw-font-xs-13')
      .copyWith(color: context.dsh.labelSecondary),
);
Widget pluginCard(
  BuildContext context, {
  required Widget child,
  VoidCallback? onTap,
}) {
  final fill = context.dsh.color('--dsw-alias-bg-layer-2');
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: fill,
      border: Border.all(
        color: context.dsh.color('--dsw-alias-border-l3'),
        width: .5,
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    // Descendants that pre-composite translucent colours must use this card's
    // opaque fill, rather than an inherited surface behind the card.
    child: DshSurface(color: fill, child: child),
  );
}

class PluginInput extends StatefulWidget {
  const PluginInput({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    this.enabled = true,
  });
  final String value, label;
  final ValueChanged<String> onChanged;
  final bool enabled;
  @override
  State<PluginInput> createState() => _PluginInputState();
}

class _PluginInputState extends State<PluginInput> {
  late final TextEditingController controller = TextEditingController(
    text: widget.value,
  );
  @override
  void didUpdateWidget(PluginInput old) {
    super.didUpdateWidget(old);
    if (controller.text != widget.value) {
      controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: TextField(
      controller: controller,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      style: context.dsh.textStyle('--dsw-font-s-14'),
      decoration: InputDecoration(labelText: widget.label, isDense: true),
    ),
  );
}

String managementErrorText(String code, String? diagnostic, DshI18n i18n) {
  final key = switch (code) {
    'management-required' => 'reasonManagementRequired',
    'unaddressable' => 'reasonUnaddressable',
    'unknown-plugin' => 'reasonUnknownPlugin',
    'invalid-spec' => 'reasonInvalidSpec',
    'already-installed' => 'reasonAlreadyInstalled',
    'ambiguous-install' => 'reasonAmbiguousInstall',
    'not-bundle' => 'reasonNotBundle',
    'not-removable' => 'reasonNotRemovable',
    'stop-profile' => 'reasonStopProfile',
    'bundle-in-use' => 'reasonBundleInUse',
    'stale-approval' => 'reasonStaleApproval',
    'incompatible-version' => 'reasonIncompatibleVersionUnnamed',
    _ => 'reasonOperationError',
  };
  if (code == 'operation-error' && diagnostic?.isNotEmpty == true) {
    return diagnostic!;
  }
  return i18n.t('pluginManager', key);
}
