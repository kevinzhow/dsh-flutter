/// Synthetic data in the actual application sidebar composition. This helper
/// deliberately has no flutter_test/parity dependency so native targets reuse it.
library;

import 'package:dsh_feature_session/dsh_feature_session.dart';
import 'package:dsh_feature_settings/dsh_feature_settings.dart';
import 'package:dsh_feature_sidebar/dsh_feature_sidebar.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_layout/dsh_layout.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

class ReportedSidebarFixture extends StatefulWidget {
  const ReportedSidebarFixture({
    super.key,
    required this.i18n,
    this.platform = ShellPlatform.darwin,
    this.collapsed = false,
    this.width = 280,
    this.onAction,
  });

  final DshI18n i18n;
  final ShellPlatform platform;
  final bool collapsed;
  final double width;
  final ValueChanged<String>? onAction;

  @override
  State<ReportedSidebarFixture> createState() => _ReportedSidebarFixtureState();
}

class _ReportedSidebarFixtureState extends State<ReportedSidebarFixture> {
  final _slots = SlotRegistry();
  final _view = WorkspaceViewState();
  final _navigator = GlobalKey<NavigatorState>();
  late final LayoutStore _layoutStore;
  late final LayoutController _layout;
  late final _SidebarServices _sidebar;
  late final void Function() _disposeSidebar;
  late final void Function() _disposeSettings;
  final _now = DateTime.utc(2026, 10, 28, 0);
  String? _current = 's2';

  @override
  void initState() {
    super.initState();
    for (final slot in DshShellSlots.all) {
      _slots.declare(slot);
    }
    _slots.declare(DshSlots.settingsSection);
    _layoutStore = LayoutStore(viewportWidth: 1280);
    _layout = LayoutController(
      _layoutStore,
      (id) => id == 'plugins' || id == 'schedule',
    );
    _sidebar = _SidebarServices(this);
    _disposeSidebar = registerSidebarFeature(_slots, services: _sidebar);
    _disposeSettings = registerSettingsShell(
      _slots,
      services: _SettingsServices(this),
    ).dispose;
    _view.setGroupExpanded('w1', true);
    for (final entry in [
      ('plugins', DshShellIcons.pluginPinwheel, 'plugins'),
      ('schedule', DshShellIcons.clock, 'schedule'),
    ]) {
      _slots.register<SidebarPanelIconOwner, Widget>(
        DshShellSlots.sidebarPanellist.typed<SidebarPanelIconOwner, Widget>(),
        (owner) => DshIcon(
          entry.$2,
          size: owner.size,
          color: context.dsh.labelPrimary,
        ),
        id: entry.$1,
        label: () => widget.i18n.t(
          entry.$3 == 'plugins' ? 'pluginManager' : 'schedule.manager',
          'panel',
        ),
      );
    }
  }

  void _action(String value) {
    widget.onAction?.call(value);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _disposeSettings();
    _disposeSidebar();
    _view.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.dsh.color('--dsw-specific-sidebar-fill'),
    child: ShellScope(
      chrome: ShellChrome(platform: widget.platform),
      child: SizedBox(
        width: widget.collapsed
            ? DshSidebarRecipe.railIconBox +
                  DshSidebarRecipe.railInlinePadding * 2
            : widget.width,
        child: Navigator(
          key: _navigator,
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => SidebarRoot(
              key: const ValueKey('reported-sidebar-root'),
              owner: SidebarOwner(
                collapsed: widget.collapsed,
                width: widget.collapsed ? 56 : widget.width,
              ),
              slots: _slots,
              services: _sidebar,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _browser(BuildContext context, SidebarSectionOwner owner) =>
      WorkspaceBrowser(
        snapshot: SessionListSnapshot(
          phase: ListPhase.ready,
          items: [
            for (var i = 1; i <= 2; i++)
              SessionListEntry(
                SessionSummary(
                  sessionId: 's$i',
                  updatedAt: _now
                      .subtract(Duration(days: i + 2))
                      .millisecondsSinceEpoch,
                  running: false,
                  blank: false,
                  agentAvailable: true,
                ),
                i == 1 ? '分析合成项目进展' : '分析下一步合成任务',
              ),
          ],
        ),
        workspaces: [
          TreeWorkspace(
            workspaceId: 'w1',
            title: 'synthetic',
            path: '/synthetic',
            createdAt: 1,
            sessionIds: const ['s1', 's2'],
          ),
          TreeWorkspace(
            workspaceId: 'w2',
            title: widget.i18n.t('workspace', 'workspace.defaultName'),
            path: '/default',
            createdAt: 2,
            sessionIds: const [],
          ),
        ],
        view: _view,
        i18n: widget.i18n,
        currentId: _layout.panelInfo.activePanelId == null ? _current : null,
        wide: owner.wide,
        now: () => _now,
        onOpen: (id) {
          _current = id;
          _action('session:$id');
        },
        onExpand: owner.expandSidebar,
        onStartInWorkspace: (id) => _action('workspace-new:$id'),
        addControl: (box, icon, ink) => GestureDetector(
          key: const ValueKey('reported-sidebar-add'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _action('add-workspace'),
          child: SizedBox.square(
            dimension: box,
            child: Center(
              child: DshIcon(
                DshShellIcons.projectAdd,
                size: icon,
                color: context.dsh.color(ink),
              ),
            ),
          ),
        ),
      );
}

class _SidebarServices implements SidebarServices {
  _SidebarServices(this.owner);
  final _ReportedSidebarFixtureState owner;
  @override
  DshI18n get i18n => owner.widget.i18n;
  @override
  LayoutController get layout => owner._layout;
  @override
  String get brandName => 'Whalee';
  @override
  ShortcutService? get shortcuts => null;
  @override
  Widget browsingRegion(BuildContext context, SidebarSectionOwner scope) =>
      owner._browser(context, scope);
  @override
  void startSession() {
    owner._current = null;
    owner._action('new-session');
  }
}

class _SettingsServices implements SettingsShellServices {
  _SettingsServices(this.owner);
  final _ReportedSidebarFixtureState owner;
  @override
  DshI18n get i18n => owner.widget.i18n;
  @override
  GlobalKey<NavigatorState> get navigatorKey => owner._navigator;
  @override
  ShortcutService? get shortcuts => null;
  @override
  bool get hostIsLocal => false;
  @override
  SettingsDocumentOpener? get documentOpener => null;
  @override
  double get overlayTop => 24;
  @override
  Widget? moreMenuHeader(BuildContext context) => null;
}
