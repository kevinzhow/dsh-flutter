/// The desktop shell as the app composes it: the three-column frame's seats are
/// filled here, from the features that own them and from the session in view.
///
/// `sidebar` is the sidebar shell (`dsh_feature_sidebar`), `sidebar.workspaces`
/// the session list, `main`/`conversation` the open session, `rightbar` its
/// right sidebar, `sidebar.settings` the settings foot, and the shortcut
/// reference and commands are registered beside them. Below the phone
/// breakpoint none of it is drawn: the phone layout stays as it was.
library;

import 'dart:async';
import 'dart:io' show InternetAddress, NetworkInterface;

import 'package:dsh_client/generated_directory_picker.dart'
    show DirectoryPickerRemote;
import 'package:dsh_client/generated.dart'
    show SessionRemote, SessionSearchRequest;
import 'package:dsh_client/generated_settings.dart' show SettingsRemote;
import 'package:dsh_feature_conversation/dsh_feature_conversation.dart'
    show ConversationHero;
import 'package:dsh_feature_directory_picker_native/dsh_feature_directory_picker_native.dart';
import 'package:dsh_feature_open_in_app/dsh_feature_open_in_app.dart';
import 'package:dsh_feature_session/dsh_feature_session.dart';
import 'package:dsh_feature_settings/dsh_feature_settings.dart';
import 'package:dsh_feature_shortcuts/dsh_feature_shortcuts.dart';
import 'package:dsh_feature_sidebar/dsh_feature_sidebar.dart';
import 'package:dsh_feature_workspace/dsh_feature_workspace.dart'
    show WorkspaceAddAction;
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_layout/dsh_layout.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'app_controller.dart';
import 'app_identity.dart';
import 'local_prefs.dart';
import 'screens/connection_bar.dart';
import 'screens/security_chip.dart';
import 'screens/session_screen.dart';

/// The id of the command that adds a workspace (dsh `workspace.add`).
const String workspaceAddCommand = 'workspace.add';

/// A global panel dsh has and Whalee does not port yet: its sidebar entry sits
/// where dsh's does and opens a "not available yet" page.
class _PanelEntry {
  const _PanelEntry(this.id, this.namespace, this.icon, this.order);

  final String id;

  /// The dsh locale namespace holding the panel's `panel` and `title` copy.
  final String namespace;
  final DshIconData icon;
  final int order;
}

final List<_PanelEntry> _panels = [
  _PanelEntry('plugins', 'pluginManager', DshShellIcons.pluginPinwheel, 0),
  _PanelEntry('schedules', 'schedule.manager', DshShellIcons.clock, 10),
];

/// Registers the desktop shell's seats for one [AppController].
class DesktopShell {
  DesktopShell(this.app) {
    final slots = app.slots;
    _offs.add(
      registerSidebarFeature(slots, services: _SidebarShellServices(this)),
    );
    _offs.add(
      slots.register<Object?, Widget>(
        DshShellSlots.main.typed<Object?, Widget>(),
        (_) => _MainConversation(app: app),
        key: conversationPanelKey,
      ),
    );
    _offs.add(
      slots.register<RightbarOwner, Widget>(
        DshShellSlots.rightbar.typed<RightbarOwner, Widget>(),
        (owner) => _Rightbar(app: app, owner: owner),
      ),
    );
    final registered = registerSettingsShell(
      slots,
      services: _SettingsShellServices(this),
    );
    settings = registered.shell;
    _offs.add(registered.dispose);
    openInApp = OpenInAppController(
      client: app.backend.openInApp,
      readChoice: () => app.prefs.openInAppChoice,
      writeChoice: (id) => unawaited(app.prefs.setOpenInAppChoice(id)),
    );
    _offs.add(openInApp.dispose);
    _offs.add(
      registerOpenInAppFeature(slots, services: _OpenInAppShellServices(this)),
    );
    _registerWorkspaceAdd();
    _registerSearchCommand();
    _offs.add(
      slots.register<SessionOwner, Widget>(
        DshSlots.conversationView.typed<SessionOwner, Widget>(),
        (_) => UnavailablePanel(
          title: app.i18n.t('trajectory', 'view.trajectory'),
          app: app,
        ),
        id: 'trajectory',
        order: 10,
        label: () => app.i18n.t('trajectory', 'view.trajectory'),
      ),
    );
    _offs.add(
      slots.register<SessionOwner, Widget>(
        DshSlots.conversationSessionHeaderUtilities
            .typed<SessionOwner, Widget>(),
        (owner) => SessionOverflowMenu(owner: owner, app: app),
        id: 'overflow',
        order: 0,
      ),
    );
    for (final panel in _panels) {
      _offs.add(
        slots.register<SidebarPanelIconOwner, Widget>(
          DshShellSlots.sidebarPanellist.typed<SidebarPanelIconOwner, Widget>(),
          (icon) => Builder(
            builder: (context) => DshIcon(
              panel.icon,
              size: icon.size,
              color: context.dsh.labelPrimary,
            ),
          ),
          id: panel.id,
          order: panel.order,
          label: () => app.i18n.t(panel.namespace, 'panel'),
        ),
      );
      _offs.add(
        slots.register<Object?, Widget>(
          DshShellSlots.main.typed<Object?, Widget>(),
          (_) => UnavailablePanel(
            title: app.i18n.t(panel.namespace, 'title'),
            app: app,
          ),
          key: panel.id,
        ),
      );
    }
    final shortcuts = app.shortcuts;
    if (shortcuts != null) {
      final reg = registerShortcutsFeature(
        slots,
        services: _ShortcutsShellServices(app),
      );
      shortcutsFeature = reg.feature;
      _offs.add(reg.dispose);
    }
    app.sidebar.currentSession = () => app.openSession?.owner;
    app.addListener(_hostChanged);
    _hostChanged();
  }

  final AppController app;
  final List<void Function()> _offs = [];

  /// The settings panel of the window.
  late final SettingsShell settings;

  /// The shortcut reference (null without a shortcut service).
  ShortcutsFeature? shortcutsFeature;

  /// Open the workspace in an application installed on the host.
  late final OpenInAppController openInApp;

  /// How the sidebar's browsing region groups and orders Sessions.
  late final WorkspaceViewState browserView = WorkspaceViewState(
    storage: _PrefsViewStorage(app.prefs),
  );

  /// Whether this build can use the host machine's own desktop: the OS chooser
  /// and the "open in" actions need a desktop window and a local host.
  bool get offersHostDesktop => hostIsLocal && isDesktopPlatform;

  void Function()? _offNative;

  /// The host's own folder chooser fills the directory-flow holes ahead of the
  /// browse flow while the host is this machine.
  void _syncNative() {
    if (offersHostDesktop && _offNative == null) {
      _offNative = registerDirectoryPickerNativeFeature(
        app.slots,
        pick: () => DirectoryPickerRemote(app.backend.remoteCaller).pick(),
      );
    } else if (!offersHostDesktop && _offNative != null) {
      _offNative!();
      _offNative = null;
    }
  }

  void _registerSearchCommand() {
    final shortcuts = app.shortcuts;
    if (shortcuts == null) return;
    String t(String key) => app.i18n.t('workspace', key);
    _offs.add(
      shortcuts.register(
        ShortcutCommand(
          id: 'session.search',
          label: () => t('search.sessions.aria'),
          aliases: const ['search sessions'],
          defaults: {
            for (final p in [
              'desktop:macos',
              'desktop:windows',
              'desktop:linux',
            ])
              p: const ShortcutBinding('KeyK', [ShortcutModifier.primary]),
            for (final p in ['web:macos', 'web:windows'])
              p: const ShortcutBinding('KeyK', [
                ShortcutModifier.primary,
                ShortcutModifier.alt,
              ]),
          },
          resolve: (_) => ShortcutHandled(browserView.requestSearch),
        ),
      ),
    );
  }

  void _registerWorkspaceAdd() {
    final shortcuts = app.shortcuts;
    if (shortcuts == null) return;
    String t(String key) => app.i18n.t('workspace', key);
    _offs.add(
      shortcuts.register(
        ShortcutCommand(
          id: workspaceAddCommand,
          label: () => t('workspace.add'),
          aliases: const ['add workspace', 'open folder'],
          defaults: {
            for (final p in [
              'desktop:macos',
              'desktop:windows',
              'desktop:linux',
            ])
              p: const ShortcutBinding('KeyO', [ShortcutModifier.primary]),
            for (final p in ['web:macos', 'web:windows'])
              p: const ShortcutBinding('KeyO', [
                ShortcutModifier.primary,
                ShortcutModifier.alt,
              ]),
          },
          resolve: (_) {
            final flow = DshSlots.sidebarWorkspacesDirectoryFlow
                .typed<DirectoryFlowOwner, Widget>();
            if (app.slots.entries(flow).isEmpty) {
              return ShortcutBlocked(t('shortcut.noPicker'));
            }
            return ShortcutHandled(browserView.requestAdd);
          },
        ),
      ),
    );
  }

  /// Whether the paired host runs on this machine (a loopback address or one of
  /// this machine's own): the OS chooser and the "open in" actions act on the
  /// host's display, which is this one.
  bool hostIsLocal = false;
  String? _checkedOrigin;

  void _hostChanged() {
    final origin = app.hostOrigin;
    if (origin == _checkedOrigin) return;
    _checkedOrigin = origin;
    if (origin == null) {
      hostIsLocal = false;
      openInApp.setEnabled(false);
      _syncNative();
      return;
    }
    unawaited(
      isLocalHost(Uri.parse(origin).host).then((local) {
        if (_checkedOrigin == origin && hostIsLocal != local) {
          hostIsLocal = local;
          openInApp.setEnabled(offersHostDesktop);
          _syncNative();
          app.notifyShellChanged();
        }
      }),
    );
  }

  /// Withdraw every occupant.
  void dispose() {
    _offNative?.call();
    _offNative = null;
    browserView.dispose();
    app.removeListener(_hostChanged);
    for (final off in _offs.reversed) {
      off();
    }
    _offs.clear();
  }
}

/// Whether [host] names this machine: a loopback address, `localhost`, or an
/// address of one of this machine's own interfaces.
Future<bool> isLocalHost(String host) async {
  if (host == 'localhost') return true;
  final address = InternetAddress.tryParse(host);
  if (address == null) return false;
  if (address.isLoopback) return true;
  try {
    for (final interface in await NetworkInterface.list()) {
      if (interface.addresses.any((a) => a.address == address.address)) {
        return true;
      }
    }
  } on Object {
    // No interface list: not local.
  }
  return false;
}

class _SidebarShellServices implements SidebarServices {
  _SidebarShellServices(this.shell);

  final DesktopShell shell;

  AppController get app => shell.app;

  @override
  DshI18n get i18n => app.i18n;

  @override
  LayoutController get layout => app.layout.controller;

  @override
  void startSession() => unawaited(app.startSession());

  @override
  Widget browsingRegion(BuildContext context, SidebarSectionOwner owner) =>
      _SessionsRegion(shell: shell, owner: owner);

  @override
  String get brandName => appDisplayName;

  @override
  ShortcutService? get shortcuts => app.shortcuts;
}

class _OpenInAppShellServices implements OpenInAppServices {
  _OpenInAppShellServices(this.shell);

  final DesktopShell shell;

  AppController get app => shell.app;

  @override
  OpenInAppController get controller => shell.openInApp;

  @override
  DshI18n get i18n => app.i18n;

  @override
  ShortcutService? get shortcuts => app.shortcuts;

  @override
  GlobalKey<NavigatorState> get navigatorKey => app.navigatorKey;

  @override
  String? currentDirectory() {
    if (app.layout.controller.panelInfo.activePanelId != null) return null;
    return app.openSession?.owner.cwdReader?.call();
  }
}

class _PrefsViewStorage implements WorkspaceViewStorage {
  _PrefsViewStorage(this.prefs);

  final LocalPrefs prefs;

  @override
  String? read() => prefs.workspaceView;

  @override
  void write(String json) => unawaited(prefs.setWorkspaceView(json));
}

class _SettingsShellServices implements SettingsShellServices {
  _SettingsShellServices(this.shell);

  final DesktopShell shell;

  AppController get app => shell.app;

  @override
  GlobalKey<NavigatorState> get navigatorKey => app.navigatorKey;

  @override
  DshI18n get i18n => app.i18n;

  @override
  ShortcutService? get shortcuts => app.shortcuts;

  @override
  bool get hostIsLocal => shell.hostIsLocal;

  @override
  SettingsDocumentOpener? get documentOpener =>
      app.hostConnected ? _DocumentOpener(app) : null;

  @override
  Widget? moreMenuHeader(BuildContext context) {
    final origin = app.hostOrigin;
    if (origin == null) return null;
    final theme = context.dsh;
    return Column(
      key: const ValueKey('host-line'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DshChromeText(
          Uri.parse(origin).authority,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme
              .textStyle('--dsw-font-xxs-12')
              .copyWith(color: theme.color('--dsw-alias-label-tertiary')),
        ),
        const SizedBox(height: 2),
        SecurityChip(controller: app),
      ],
    );
  }

  @override
  double get overlayTop => 24;
}

/// The host's settings document, over the `settings` Remote.
class _DocumentOpener implements SettingsDocumentOpener {
  _DocumentOpener(this.app);

  final AppController app;

  @override
  Future<bool> available() async {
    try {
      return (await SettingsRemote(
        app.backend.remoteCaller,
      ).describe()).hasDocument;
    } on Object {
      return false;
    }
  }

  @override
  Future<String?> open() async {
    try {
      await SettingsRemote(app.backend.remoteCaller).openSettingsDocument();
      return null;
    } on Object catch (e) {
      return '$e';
    }
  }
}

class _ShortcutsShellServices implements ShortcutsServices {
  _ShortcutsShellServices(this.app);

  final AppController app;

  @override
  GlobalKey<NavigatorState> get navigatorKey => app.navigatorKey;

  @override
  DshI18n get i18n => app.i18n;

  @override
  ShortcutService get shortcuts => app.shortcuts!;
}

List<String>? _keysOf(ShortcutService? shortcuts, String id) {
  final entry = shortcuts?.registry.entry(id);
  return entry == null || entry.keys.isEmpty ? null : entry.keys;
}

/// The browsing region: the connection feedback, then the session list.
class _SessionsRegion extends StatelessWidget {
  const _SessionsRegion({required this.shell, required this.owner});

  final DesktopShell shell;
  final SidebarSectionOwner owner;

  AppController get app => shell.app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final theme = context.dsh;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConnectionBar(controller: app),
            if (app.createError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: DshChromeText(
                  '${app.i18n.t(appNamespace, 'sessions.createFailed')}: ${app.createError}',
                  key: const ValueKey('create-error'),
                  style: theme
                      .textStyle('--dsw-font-xxs-12')
                      .copyWith(
                        color: theme.color('--dsw-alias-state-error-primary'),
                      ),
                ),
              ),
            Expanded(
              child: StreamBuilder<WorkspaceSnapshot>(
                stream: app.workspaceState.changes,
                initialData: app.workspaceState.value,
                builder: (context, snap) => _browser(snap.data!),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _browser(WorkspaceSnapshot hosted) {
    final defaultName = app.i18n.t('conversation', 'workspace.defaultName');
    return WorkspaceBrowser(
      snapshot: app.sessionList,
      management: app.workspaceManagement,
      hostHome: app.hostHome,
      slots: app.slots,
      workspaces: [
        for (final w in hosted.items)
          TreeWorkspace(
            workspaceId: w.workspaceId,
            title: workspaceDisplayTitle(w.title, defaultName),
            path: w.path,
            createdAt:
                DateTime.tryParse(w.createdAt)?.millisecondsSinceEpoch ?? 0,
            sessionIds: w.sessionIds,
          ),
      ],
      rowState: SessionRowState(
        pinned: hosted.pinnedSessionIds,
        archived: hosted.archivedSessionIds,
      ),
      workspaceReady: hosted.phase == WorkspacePhase.ready,
      onStartInWorkspace: (id) {
        unawaited(app.startSession(id));
        owner.navigated?.call();
      },
      view: shell.browserView,
      i18n: app.i18n,
      currentId: app.layout.controller.panelInfo.activePanelId == null
          ? app.openSessionId
          : null,
      onOpen: (id) {
        unawaited(app.open(id));
        owner.navigated?.call();
      },
      wide: owner.wide,
      onExpand: owner.expandSidebar,
      addControl: (box, icon, ink) => WorkspaceAddAction(
        owner: SidebarWorkspacesOwner(onStarted: () {}),
        services: app.workspaceServices,
        slots: app.slots,
        i18n: app.i18n,
        box: box,
        iconSize: icon,
        inkToken: ink,
        requests: shell.browserView.addRequests,
      ),
      addKeys: _keysOf(app.shortcuts, workspaceAddCommand),
      searchKeys: _keysOf(app.shortcuts, 'session.search'),
      newKeys: _keysOf(app.shortcuts, 'session.new'),
      search: (query) async {
        final found = await SessionRemote(app.backend.remoteCaller)
            .search(SessionSearchRequest(query: query));
        return RemoteSearchResult([
          for (final i in found.items) ContentMatch(i.sessionId, i.snippet),
        ], found.hasMore);
      },
    );
  }
}

/// The Conversation of the session in view, or the empty state.
class _MainConversation extends StatelessWidget {
  const _MainConversation({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final session = app.openSession;
        if (session == null) {
          // dsh's sessionless hero: choose a workspace first.
          final hero = ConversationHero(
            key: const ValueKey('new-session'),
            owner: null,
            slots: app.slots,
            i18n: app.i18n,
            workspaces: app.workspaceServices,
          );
          final phone = PhoneChrome.maybeOf(context);
          return phone == null
              ? hero
              : Column(
                  children: [
                    PhoneTopBar(title: '', chrome: phone),
                    Expanded(child: hero),
                  ],
                );
        }
        return SessionView(
          key: ValueKey('session-${session.sessionId}'),
          controller: app,
          session: session,
        );
      },
    );
  }
}

/// The right column's occupant: the sidebar of the session in view, with the
/// geometry the frame solved.
class _Rightbar extends StatelessWidget {
  const _Rightbar({required this.app, required this.owner});

  final AppController app;
  final RightbarOwner owner;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final session = app.openSession;
        if (session == null) return const SizedBox.shrink();
        final seat = app.slots.renderSingle(
          DshSlots.rightbarSession.typed<SessionOwner, Widget>(),
          session.owner,
        );
        if (seat == null) return const SizedBox.shrink();
        return DshRightbarGeometry(
          width: owner.width,
          viewportWidth: owner.viewportWidth,
          canShow: owner.canShow,
          child: KeyedSubtree(
            key: ValueKey('rightbar-${session.sessionId}'),
            child: seat,
          ),
        );
      },
    );
  }
}

/// The page of a panel Whalee does not have yet.
class UnavailablePanel extends StatelessWidget {
  const UnavailablePanel({super.key, required this.title, required this.app});

  final String title;
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Center(
      key: const ValueKey('panel-unavailable'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DshChromeText(
            title,
            style: theme
                .textStyle('--dsw-font-base-strong-16')
                .copyWith(color: theme.labelPrimary),
          ),
          const SizedBox(height: 8),
          DshChromeText(
            app.i18n.t(
              appNamespace,
              'panel.unavailable.body',
              params: {'name': title},
            ),
            textAlign: TextAlign.center,
            style: theme
                .textStyle('--dsw-font-s-14')
                .copyWith(color: theme.labelSecondary),
          ),
        ],
      ),
    );
  }
}

/// The Session overflow menu of the header (dsh `More actions`): the Session
/// verbs Whalee can act on. Rename, fork, archive and pin are not ported yet.
class SessionOverflowMenu extends StatelessWidget {
  const SessionOverflowMenu({
    super.key,
    required this.owner,
    required this.app,
  });

  final SessionOwner owner;
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final hosted = app.workspaceState.value;
    return WorkspaceSessionMenu(
      actions: app.workspaceManagement,
      slots: app.slots,
      i18n: app.i18n,
      sessionId: owner.sessionId,
      title: (owner.session.projections.get('title') as String?) ?? '',
      pinned: hosted.pinnedSessionIds.contains(owner.sessionId),
      archived: hosted.archivedSessionIds.contains(owner.sessionId),
      builder: (context, menu) => DshTooltip(
        label: app.i18n.t(
          'workspace',
          'actions.session.aria',
          params: {
            'name': (owner.session.projections.get('title') as String?) ?? '',
          },
        ),
        side: DshTooltipSide.bottom,
        delay: const Duration(milliseconds: 500),
        child: GestureDetector(
          key: const ValueKey('session-overflow'),
          behavior: HitTestBehavior.opaque,
          onTap: menu.toggle,
          child: DshContainer(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(theme.radiusSm),
            ),
            child: DshIcon(
              DshShellIcons.ellipsis,
              size: 15,
              color: theme.labelSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
