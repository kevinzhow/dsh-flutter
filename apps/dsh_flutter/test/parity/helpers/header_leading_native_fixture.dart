// The actual Header occupant with synthetic actions, independent of AppFrame's
// platform/mounting policy. No product styles or alternative buttons live here.
import 'package:dsh_feature_sidebar/dsh_feature_sidebar.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_layout/dsh_layout.dart';
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

class HeaderLeadingNativeFixture extends StatefulWidget {
  const HeaderLeadingNativeFixture({super.key, required this.i18n});
  final DshI18n i18n;

  @override
  State<HeaderLeadingNativeFixture> createState() =>
      _HeaderLeadingNativeFixtureState();
}

class _HeaderLeadingNativeFixtureState
    extends State<HeaderLeadingNativeFixture> {
  final _scope = FocusScopeNode(debugLabel: 'native Header replay');
  final _store = LayoutStore(viewportWidth: 1280);
  late final _layout = LayoutController(_store, (_) => false);
  late final _services = _Services(this);
  late final void Function() _off;
  int toggles = 0, sessions = 0;

  @override
  void initState() {
    super.initState();
    _off = _store.subscribe(() => setState(() => toggles++));
    // Enter an empty focus scope. Its first Tab reaches the actual Header
    // buttons, while the initial scene has no programmatically painted ring.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scope.requestFocus();
    });
  }

  void _newSession() => setState(() => sessions++);

  @override
  void dispose() {
    _off();
    _layout.dispose();
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FocusScope(
    node: _scope,
    child: Align(
      alignment: Alignment.topLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(DshHeaderLeadingRecipe.controlsGap),
            child: DshSurface(
              color: context.dsh.bgBase,
              child: ShellScope(
                chrome: const ShellChrome(platform: ShellPlatform.darwin),
                child: SidebarLeadingControls(
                  services: _services,
                  collapsed: true,
                ),
              ),
            ),
          ),
          Text('Header callbacks: toggle=$toggles session=$sessions'),
        ],
      ),
    ),
  );
}

class _Services implements SidebarServices {
  const _Services(this.owner);
  final _HeaderLeadingNativeFixtureState owner;
  @override
  DshI18n get i18n => owner.widget.i18n;
  @override
  LayoutController get layout => owner._layout;
  @override
  void startSession() => owner._newSession();
  @override
  String get brandName => 'Whalee';
  @override
  ShortcutService? get shortcuts => null;
  @override
  Widget browsingRegion(BuildContext context, SidebarSectionOwner owner) =>
      const SizedBox.shrink();
}
