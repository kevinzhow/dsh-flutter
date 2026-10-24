import 'slot.dart';

/// The slots of dsh's desktop three-column shell (dsh `ui-layout`,
/// `ui-sidebar` and `ui-settings` `SlotMap` declarations): the frame's own
/// seats and the sidebar and settings chrome seats inside them. They are
/// root-scoped: a Session is never bound to them.
abstract final class DshShellSlots {
  /// The whole left column (`ui-layout`). Occupied by the sidebar shell.
  static const sidebar = Slot<Object?, Object?>(
    'sidebar',
    SlotCardinality.single,
    SlotScope.root,
  );

  /// The central panel selected by sidebar entry id (`ui-layout`, keyed); the
  /// reserved key `conversation` hosts the Conversation.
  static const main = Slot<Object?, Object?>(
    'main',
    SlotCardinality.keyed,
    SlotScope.root,
  );

  /// The right column (`ui-layout`): a track the centre makes room for.
  static const rightbar = Slot<Object?, Object?>(
    'rightbar',
    SlotCardinality.single,
    SlotScope.root,
  );

  /// Full-width bottom content below all three columns (`ui-layout`).
  static const shellBottom = Slot<Object?, Object?>(
    'shell.bottom',
    SlotCardinality.single,
    SlotScope.root,
  );

  /// Frame-wide floating layer above every column (`ui-layout`).
  static const shellOverlay = Slot<Object?, Object?>(
    'shell.overlay',
    SlotCardinality.list,
    SlotScope.root,
  );

  /// Window-chrome seat at the frame's top-left, mounted only while the
  /// sidebar column is fully hidden (`ui-layout`, macOS and Windows desktop).
  static const shellLeading = Slot<Object?, Object?>(
    'shell.leading',
    SlotCardinality.single,
    SlotScope.root,
  );

  /// Brand mark of the expanded brand row and the collapsed rail (`ui-sidebar`).
  static const sidebarBrandMark = Slot<Object?, Object?>(
    'sidebar.brand.mark',
    SlotCardinality.single,
    SlotScope.root,
  );

  /// Brand name beside the expanded mark (`ui-sidebar`).
  static const sidebarBrandName = Slot<Object?, Object?>(
    'sidebar.brand.name',
    SlotCardinality.single,
    SlotScope.root,
  );

  /// Non-interactive notification inside the collapsed expand button
  /// (`ui-sidebar`).
  static const sidebarToggleBadge = Slot<Object?, Object?>(
    'sidebar.toggle.badge',
    SlotCardinality.single,
    SlotScope.root,
  );

  /// Global panel icons (`ui-sidebar`); each list id addresses the matching
  /// `main` key.
  static const sidebarPanellist = Slot<Object?, Object?>(
    'sidebar.panellist',
    SlotCardinality.list,
    SlotScope.root,
  );

  /// The settings seat at the sidebar foot (`ui-sidebar`).
  static const sidebarSettings = Slot<Object?, Object?>(
    'sidebar.settings',
    SlotCardinality.single,
    SlotScope.root,
  );

  /// Optional actions beside Settings at the sidebar foot (`ui-sidebar`).
  static const sidebarFooterAction = Slot<Object?, Object?>(
    'sidebar.footer.action',
    SlotCardinality.list,
    SlotScope.root,
  );

  /// Optional sidebar account launcher that opens the settings panel
  /// (`ui-settings`).
  static const settingsLauncher = Slot<Object?, Object?>(
    'settings.launcher',
    SlotCardinality.single,
    SlotScope.root,
  );

  /// The sidebar-foot trigger row content: icon and label (`ui-settings`).
  static const settingsTrigger = Slot<Object?, Object?>(
    'settings.trigger',
    SlotCardinality.single,
    SlotScope.root,
  );

  /// The panel title text seat (`ui-settings`).
  static const settingsHeader = Slot<Object?, Object?>(
    'settings.header',
    SlotCardinality.single,
    SlotScope.root,
  );

  /// Optional actions in the content column's header before Close
  /// (`ui-settings`).
  static const settingsAction = Slot<Object?, Object?>(
    'settings.action',
    SlotCardinality.list,
    SlotScope.root,
  );

  /// The close button's accessible label text (`ui-settings`).
  static const settingsClose = Slot<Object?, Object?>(
    'settings.close',
    SlotCardinality.single,
    SlotScope.root,
  );

  /// Global navigation before the Session title, available without a Session
  /// (`ui-conversation`).
  static const conversationHeaderLeading = Slot<Object?, Object?>(
    'conversation.header.leading',
    SlotCardinality.single,
    SlotScope.root,
  );

  static const all = <Slot<Object?, Object?>>[
    sidebar,
    main,
    rightbar,
    shellBottom,
    shellOverlay,
    shellLeading,
    sidebarBrandMark,
    sidebarBrandName,
    sidebarToggleBadge,
    sidebarPanellist,
    sidebarSettings,
    sidebarFooterAction,
    settingsLauncher,
    settingsTrigger,
    settingsHeader,
    settingsAction,
    settingsClose,
    conversationHeaderLeading,
  ];
}

/// Owner props of `sidebar` (dsh `SidebarOwnerProps`): the live column state
/// from the frame's concession solve.
class SidebarOwner {
  const SidebarOwner({
    required this.collapsed,
    required this.width,
    this.drawer = false,
  });

  /// The column is a phone drawer: the expanded sidebar over the page, with no
  /// collapse control, closing when something in it is picked.
  final bool drawer;

  /// True when the sidebar is closed (the column renders the compact rail).
  final bool collapsed;

  /// Rendered column width in px (the rail's width when collapsed).
  final double width;
}

/// Owner props of `rightbar` (dsh `RightbarOwnerProps`).
class RightbarOwner {
  const RightbarOwner({
    required this.width,
    required this.viewportWidth,
    required this.canShow,
  });

  /// Resolved normal panel width in px, not the saved preference; zero if it
  /// cannot fit.
  final double width;

  /// Current frame width in px.
  final double viewportWidth;

  /// Whether a normal right panel can retain 300px beside a 400px centre.
  final bool canShow;
}

/// Owner props of `sidebar.workspaces` (dsh `SidebarSectionOwnerProps`).
class SidebarSectionOwner {
  const SidebarSectionOwner({
    required this.wide,
    required this.expandSidebar,
    this.navigated,
  });

  /// Called after a Session or panel was picked; a phone drawer closes then.
  final void Function()? navigated;

  /// Wide renders the full browser, the rail its icon column.
  final bool wide;

  /// Rail icons request expansion.
  final void Function() expandSidebar;
}

/// Owner props of `sidebar.settings` and `sidebar.footer.action` (dsh
/// `SidebarSettingsOwnerProps`, `SidebarFooterActionOwnerProps`).
class SidebarFootOwner {
  const SidebarFootOwner({required this.wide});

  /// Whether the sidebar renders wide content (false: the rail).
  final bool wide;
}

/// Owner props of `sidebar.brand.mark` (dsh `SidebarBrandMarkOwnerProps`).
class SidebarBrandMarkOwner {
  const SidebarBrandMarkOwner({required this.size});

  /// Requested square edge in logical pixels.
  final double size;
}

/// Owner props of `sidebar.panellist` (dsh `SidebarPanelIconOwnerProps`).
class SidebarPanelIconOwner {
  const SidebarPanelIconOwner({required this.size, required this.active});

  final double size;

  /// Whether this panel is selected in the main column.
  final bool active;
}

/// Owner props of `settings.trigger` and `settings.launcher` (dsh
/// `SettingsTriggerOwnerProps`, `SettingsLauncherOwnerProps`).
class SettingsTriggerOwner {
  const SettingsTriggerOwner({
    required this.wide,
    this.settingsOpen = false,
    this.openSettings,
  });

  final bool wide;
  final bool settingsOpen;

  /// Opens the settings panel (launchers only).
  final void Function()? openSettings;
}

/// Owner props of the settings header seats (`settings.header`,
/// `settings.action`, `settings.close`); the surface supplies nothing, an
/// occupant draws its own copy.
class SettingsHeaderOwner {
  const SettingsHeaderOwner();
}
