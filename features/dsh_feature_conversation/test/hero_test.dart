import 'package:dsh_client/generated_workspace.dart' as ws;
import 'package:dsh_feature_conversation/dsh_feature_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ws.WorkspaceView view(
  String id,
  String title, {
  List<String> sessions = const [],
}) => ws.WorkspaceView(
  workspaceId: id,
  path: '/work/$title',
  title: title,
  sessionIds: sessions,
  createdAt: '2026-10-01T00:00:00.000Z',
  updatedAt: '2026-10-01T00:00:00.000Z',
);

class Services implements WorkspaceServices {
  Services(
    List<ws.WorkspaceView> items, {
    WorkspacePhase phase = WorkspacePhase.ready,
  }) : state = Observable(WorkspaceSnapshot(items: items, phase: phase));

  final Observable<WorkspaceSnapshot> state;
  final List<(String, String?)> opened = [];
  Object? failWith;

  @override
  Observable<WorkspaceSnapshot> get workspaces => state;

  @override
  Future<ws.WorkspaceView> createWorkspace(String path) =>
      Future.error(UnimplementedError());

  @override
  Future<void> startSession([String? workspaceId]) async {}

  @override
  Future<void> openWorkspace(String workspaceId, {String? from}) async {
    opened.add((workspaceId, from));
    if (failWith != null) throw failWith!;
  }
}

void main() {
  late SlotRegistry slots;
  late Services services;
  late List<HeroWorkspaceOwner> pickers;
  late Session session;
  late bool? blank;
  late String? cwd;

  SessionOwner owner() => testSessionOwner(
    's1',
    session: session,
    cwdReader: () => cwd,
    blankReader: () => blank,
  );

  void tw(
    String name,
    Future<void> Function(WidgetTester t) body,
  ) => testWidgets(name, (t) async {
    services = Services([
      view('wa', 'alpha', sessions: ['s1']),
      view('wb', 'beta'),
    ]);
    pickers = [];
    blank = true;
    cwd = '/work/alpha';
    session = Session('s1', FakeTransport());
    slots = SlotRegistry();
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    registerConversationFeature(
      slots,
      i18n: () => const DshI18n(DshLocale.en),
      workspaces: services,
    );
    slots.register<HeroWorkspaceOwner, Widget>(
      DshSlots.conversationHeroWorkspace.typed<HeroWorkspaceOwner, Widget>(),
      (o) {
        pickers.add(o);
        return SizedBox(key: ValueKey('picker-${o.open}'), width: 1, height: 1);
      },
    );
    await body(t);
    await t.pumpWidget(const SizedBox());
  });

  Future<void> pump(
    WidgetTester t, {
    Size size = const Size(400, 800),
    DshLocale locale = DshLocale.en,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      dshTestApp(
        slots.renderSingle(
          DshSlots.conversationSession.typed<SessionOwner, Widget>(),
          owner(),
        )!,
      ),
    );
    await t.pump();
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  tw(
    'a blank session shows the headline, the Preview badge, the chip and the composer',
    (t) async {
      await pump(t);
      expect(key('hero'), findsOneWidget);
      expect(find.text('Into the Unknown'), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);
      expect(find.text('alpha'), findsOneWidget);
      expect(key('composer-send'), findsOneWidget);
      // One rounded card: the controls row sits inside it, under the draft.
      expect(
        t.getRect(key('composer-tools')).top,
        greaterThan(t.getRect(find.byType(TextField)).bottom),
      );
      final field = t.widget<TextField>(find.byType(TextField));
      expect(
        field.decoration!.hintText,
        startsWith('Describe what you want to build'),
      );
    },
  );

  tw('a session that is not provably blank shows no hero while it loads', (
    t,
  ) async {
    blank = false;
    await pump(t);
    expect(key('hero'), findsNothing);
    expect(key('session-loading'), findsOneWidget);
  });

  tw(
    'chip label: the workspace of the session, else the folder while the list loads, else the call to action',
    (t) async {
      services.state.set(
        WorkspaceSnapshot(
          items: [
            view('wa', 'alpha', sessions: ['s1']),
          ],
        ),
      );
      await pump(t);
      expect(find.text('alpha'), findsOneWidget);
      await t.pumpWidget(const SizedBox());

      // List still pending: the session's folder bridges.
      services.state.set(const WorkspaceSnapshot());
      await pump(t);
      expect(find.text('alpha'), findsOneWidget);
      await t.pumpWidget(const SizedBox());

      // Ready, but nothing owns the session (deleted): never the folder name.
      services.state.set(
        WorkspaceSnapshot(
          items: [view('wb', 'beta')],
          phase: WorkspacePhase.ready,
        ),
      );
      await pump(t);
      expect(find.text('alpha'), findsNothing);
      expect(find.text('Choose workspace'), findsOneWidget);
    },
  );

  tw('the automatic first-use title reads as the localized default', (t) async {
    services.state.set(
      WorkspaceSnapshot(
        items: [
          view('wd', 'default-workspace', sessions: ['s1']),
        ],
        phase: WorkspacePhase.ready,
      ),
    );
    await pump(t);
    expect(find.text('Default workspace'), findsOneWidget);
  });

  tw('the chip toggles the picker slot open and closed', (t) async {
    await pump(t);
    expect(pickers.last.open, isFalse);
    await t.tap(key('hero-workspace-chip'));
    await t.pump();
    expect(pickers.last.open, isTrue);
    expect(pickers.last.selectedId, 'wa');
    await t.tap(key('hero-workspace-chip'));
    await t.pump();
    expect(pickers.last.open, isFalse);
  });

  tw('a pick opens that workspace for this session and shows it at once', (
    t,
  ) async {
    await pump(t);
    await t.tap(key('hero-workspace-chip'));
    await t.pump();
    pickers.last.onPick('wb');
    await t.pump();
    expect(services.opened, [('wb', 's1')]);
    expect(pickers.last.open, isFalse);
    // The pick shows as selected while the session is still being swapped.
    expect(pickers.last.selectedId, 'wb');
    expect(find.text('beta'), findsOneWidget);
  });

  tw('a refused pick reverts the chip and says why', (t) async {
    services.failWith = StateError('disk full');
    await pump(t);
    pickers.last.onPick('wb');
    await t.pump();
    await t.pump();
    expect(find.text('alpha'), findsOneWidget);
    expect(key('hero-error'), findsOneWidget);
    expect(find.textContaining('disk full'), findsOneWidget);
  });

  tw('a wide window centers the stack: headline, then chip, then composer', (
    t,
  ) async {
    await pump(t, size: const Size(1100, 800));
    final head = t.getRect(key('hero-headline'));
    final chip = t.getRect(key('hero-workspace-chip'));
    final send = t.getRect(key('composer-send'));
    expect(head.bottom, lessThan(chip.top));
    expect(chip.bottom, lessThan(send.top));
    // The whole stack sits in the middle of the area, not against the bottom.
    expect(send.bottom, lessThan(700));
    expect(head.center.dx, closeTo(550, 120));
  });

  tw('a phone gets the same centered stack, composer card sides 16px in', (
    t,
  ) async {
    await pump(t, size: const Size(400, 800));
    final head = t.getRect(key('hero-headline'));
    final chip = t.getRect(key('hero-workspace-chip'));
    final card = t.getRect(key('composer-tools'));
    expect(head.bottom, lessThan(chip.top));
    expect(chip.bottom, lessThan(card.top));
    // Centered in the area, not pinned to the bottom edge.
    expect(card.bottom, lessThan(700));
    expect(head.top, greaterThan(200));
    expect(chip.height, 28);
    final field = t.getRect(find.byType(TextField));
    expect(field.left, 16 + 14);
  });

  tw('the first message leaves the hero for the conversation', (t) async {
    await pump(t);
    expect(key('hero'), findsOneWidget);
    session.handleBlank(false);
    await t.pump();
    expect(key('hero'), findsNothing);
  });

  tw('without a workspace service the chip only echoes the folder', (t) async {
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final bare = SlotRegistry();
    for (final s in DshSlots.all) {
      bare.declare(s);
    }
    registerConversationFeature(bare, i18n: () => const DshI18n(DshLocale.en));
    await t.pumpWidget(
      dshTestApp(
        bare.renderSingle(
          DshSlots.conversationSession.typed<SessionOwner, Widget>(),
          owner(),
        )!,
      ),
    );
    await t.pump();
    expect(find.text('alpha'), findsOneWidget);
    await t.tap(key('hero-workspace-chip'));
    await t.pump();
    expect(pickers, isEmpty);
  });

  tw('the sessionless hero: Choose workspace and the inert dashed card', (
    t,
  ) async {
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    const i18n = DshI18n(DshLocale.en);
    await t.pumpWidget(
      dshTestApp(
        ConversationHero(
          owner: null,
          slots: slots,
          i18n: i18n,
          workspaces: services,
        ),
      ),
    );
    await t.pump();
    expect(find.text('Choose workspace'), findsOneWidget);
    expect(key('inert-composer'), findsOneWidget);
    expect(find.text('Choose a workspace to start'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    // The whole card is the pick target.
    await t.tap(key('inert-composer'));
    await t.pump();
    expect(pickers.last.open, isTrue);
    expect(pickers.last.selectedId, isNull);
    pickers.last.onPick('wb');
    await t.pump();
    expect(services.opened, [('wb', null)]);
  });

  tw('zh', (t) async {
    slots = SlotRegistry();
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    registerConversationFeature(
      slots,
      i18n: () => const DshI18n(DshLocale.zh),
      workspaces: services,
    );
    await pump(t);
    expect(find.text('探索未至之境'), findsOneWidget);
    expect(find.text('预览版'), findsOneWidget);
    final field = t.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.hintText, startsWith('描述你想要构建的内容'));
  });
}
