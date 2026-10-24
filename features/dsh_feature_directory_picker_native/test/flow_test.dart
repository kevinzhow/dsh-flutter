import 'dart:async';

import 'package:dsh_feature_directory_picker_native/dsh_feature_directory_picker_native.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> events;

  DirectoryFlowOwner owner({required bool open}) => DirectoryFlowOwner(
    open: open,
    busy: false,
    onPicked: (p) => events.add('picked $p'),
    onCancel: () => events.add('cancel'),
    onError: (m) => events.add('error $m'),
  );

  setUp(() => events = []);

  Future<void> pump(
    WidgetTester t,
    bool open,
    Future<String?> Function() pick,
  ) => t.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: NativeDirectoryFlow(
        owner: owner(open: open),
        pick: pick,
      ),
    ),
  );

  testWidgets('one chooser per open, one outcome', (t) async {
    var calls = 0;
    Future<String?> pick() async {
      calls++;
      return '/work/a';
    }

    await pump(t, false, pick);
    expect(calls, 0);
    await pump(t, true, pick);
    await pump(t, true, pick);
    await t.pump();
    expect(calls, 1);
    expect(events, ['picked /work/a']);
    // Withdrawing re-arms the next request.
    await pump(t, false, pick);
    await pump(t, true, pick);
    await t.pump();
    expect(calls, 2);
  });

  testWidgets('a dismissed chooser cancels, a failure reports its message', (
    t,
  ) async {
    await pump(t, true, () async => null);
    await t.pump();
    expect(events, ['cancel']);
    events.clear();
    await pump(t, false, () async => null);
    await pump(t, true, () => Future<String?>.error('denied'));
    await t.pump();
    expect(events, ['error denied']);
  });

  testWidgets('an answer after the occupant left is dropped', (t) async {
    final answer = Completer<String?>();
    await pump(t, true, () => answer.future);
    await t.pumpWidget(const SizedBox());
    answer.complete('/late');
    await t.pump();
    expect(events, isEmpty);
  });

  testWidgets('the holes take it ahead of the browse flow', (t) async {
    final slots = SlotRegistry();
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    final flow = DshSlots.sidebarWorkspacesDirectoryFlow
        .typed<DirectoryFlowOwner, Widget>();
    slots.register<DirectoryFlowOwner, Widget>(
      flow,
      (_) => const Text('browse', textDirection: TextDirection.ltr),
    );
    final off = registerDirectoryPickerNativeFeature(
      slots,
      pick: () async => '/x',
    );
    final first = slots.renderSingle(flow, owner(open: false));
    expect(first, isA<NativeDirectoryFlow>());
    off();
    expect(slots.renderSingle(flow, owner(open: false)), isA<Text>());
  });
}
