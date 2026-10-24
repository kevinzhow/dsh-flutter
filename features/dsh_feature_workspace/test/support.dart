import 'dart:async';

import 'package:dsh_client/dsh_client.dart' show RemoteException;
import 'package:dsh_client/generated_workspace.dart' as ws;
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ws.WorkspaceView view(
  String id, {
  String? title,
  List<String> sessions = const [],
}) => ws.WorkspaceView(
  workspaceId: id,
  path: '/work/$id',
  title: title ?? id,
  sessionIds: sessions,
  createdAt: '2026-10-01T00:00:00.000Z',
  updatedAt: '2026-10-01T00:00:00.000Z',
);

class FakeServices implements WorkspaceServices {
  FakeServices({
    List<ws.WorkspaceView> items = const [],
    WorkspacePhase phase = WorkspacePhase.ready,
  }) : state = Observable(WorkspaceSnapshot(items: items, phase: phase));

  final Observable<WorkspaceSnapshot> state;
  final List<String> created = [];
  final List<String?> started = [];
  final List<(String, String?)> opened = [];
  Object? createError;
  Completer<void>? createGate;

  @override
  Observable<WorkspaceSnapshot> get workspaces => state;

  void set(
    List<ws.WorkspaceView> items, {
    WorkspacePhase phase = WorkspacePhase.ready,
  }) => state.set(WorkspaceSnapshot(items: items, phase: phase));

  @override
  Future<ws.WorkspaceView> createWorkspace(String path) async {
    created.add(path);
    await createGate?.future;
    final error = createError;
    if (error != null) throw error;
    final w = view('new-${created.length}', title: path.split('/').last);
    set([...state.value.items, w]);
    return w;
  }

  @override
  Future<void> startSession([String? workspaceId]) async =>
      started.add(workspaceId);

  @override
  Future<void> openWorkspace(String workspaceId, {String? from}) async =>
      opened.add((workspaceId, from));
}

/// A directory-flow occupant that shows what the owner asked and lets a test
/// pick, cancel or fail by key.
class FakeFlow extends StatelessWidget {
  const FakeFlow({super.key, required this.owner});

  final DirectoryFlowOwner owner;

  @override
  Widget build(BuildContext context) {
    if (!owner.open) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          owner.busy ? 'flow busy' : 'flow open',
          key: const ValueKey('flow-state'),
        ),
        TextButton(
          key: const ValueKey('flow-pick'),
          onPressed: () => owner.onPicked('/work/picked'),
          child: const Text('pick'),
        ),
        TextButton(
          key: const ValueKey('flow-cancel'),
          onPressed: owner.onCancel,
          child: const Text('cancel'),
        ),
        TextButton(
          key: const ValueKey('flow-fail'),
          onPressed: () => owner.onError('denied by the host'),
          child: const Text('fail'),
        ),
      ],
    );
  }
}

RemoteException refusal(String message) =>
    RemoteException('workspace/invalid-path', message);

SlotRegistry newSlots({bool heroFlow = true, bool sidebarFlow = true}) {
  final slots = SlotRegistry();
  for (final s in DshSlots.all) {
    slots.declare(s);
  }
  if (heroFlow) {
    slots.register<DirectoryFlowOwner, Widget>(
      DshSlots.conversationHeroWorkspaceDirectoryFlow
          .typed<DirectoryFlowOwner, Widget>(),
      (o) => FakeFlow(owner: o),
    );
  }
  if (sidebarFlow) {
    slots.register<DirectoryFlowOwner, Widget>(
      DshSlots.sidebarWorkspacesDirectoryFlow
          .typed<DirectoryFlowOwner, Widget>(),
      (o) => FakeFlow(owner: o),
    );
  }
  return slots;
}

Future<void> useSize(WidgetTester t, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget app(Widget child, {Brightness brightness = Brightness.light}) =>
    dshTestApp(child, brightness: brightness);

/// A stand-in for the hero chip: a target the picker hangs from.
class ChipHost extends StatefulWidget {
  const ChipHost({
    super.key,
    required this.services,
    required this.slots,
    required this.i18n,
    required this.log,
    this.selectedId,
    this.initiallyOpen = false,
  });

  final FakeServices services;
  final SlotRegistry slots;
  final DshI18n i18n;
  final List<String> log;
  final String? selectedId;
  final bool initiallyOpen;

  @override
  State<ChipHost> createState() => ChipHostState();
}

class ChipHostState extends State<ChipHost> {
  final LayerLink link = LayerLink();
  late bool open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final picker = widget.slots.renderSingle(
      DshSlots.conversationHeroWorkspace.typed<HeroWorkspaceOwner, Widget>(),
      HeroWorkspaceOwner(
        open: open,
        selectedId: widget.selectedId,
        anchor: link,
        onPick: (id) {
          widget.log.add('pick:$id');
          setState(() => open = false);
        },
        onClose: () {
          widget.log.add('close');
          if (open) setState(() => open = false);
        },
      ),
    );
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 40, 0, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TapRegion(
              groupId: link,
              child: CompositedTransformTarget(
                link: link,
                child: GestureDetector(
                  key: const ValueKey('chip'),
                  onTap: () => setState(() => open = !open),
                  child: const SizedBox(
                    width: 160,
                    height: 28,
                    child: Text('chip'),
                  ),
                ),
              ),
            ),
            ?picker,
          ],
        ),
      ),
    );
  }
}

DshI18n i18n([DshLocale l = DshLocale.en]) => DshI18n(l);
