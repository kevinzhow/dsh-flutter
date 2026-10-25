import 'package:flutter/widgets.dart';

/// Resets only nested disclosure choices when an outer process actually hides
/// them. Keeping widgets mounted preserves every other renderer-owned state.
class DshDisclosureReset extends InheritedWidget {
  const DshDisclosureReset({
    super.key,
    required this.version,
    required super.child,
  });
  final int version;
  static int of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DshDisclosureReset>()
          ?.version ??
      0;
  @override
  bool updateShouldNotify(DshDisclosureReset oldWidget) =>
      oldWidget.version != version;
}

/// A reading action dispatched before the disclosure changes its layout.
/// The enclosing timeline can hold the header in place while content grows.
class DshDisclosureChange extends Notification {
  const DshDisclosureChange(this.open, this.anchor);
  final bool open;
  final BuildContext anchor;
}
