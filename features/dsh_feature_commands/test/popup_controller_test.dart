import 'dart:async';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_commands/dsh_feature_commands.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> tick() => Future<void>.delayed(Duration.zero);

const options = [
  SelectOption(
    id: 'a/flash',
    label: 'deepseek-flash',
    group: SelectOptionGroup(name: 'a', label: 'Account'),
    active: true,
  ),
  SelectOption(
    id: 'a/pro',
    label: 'deepseek-pro',
    group: SelectOptionGroup(name: 'a', label: 'Account'),
  ),
  SelectOption(
    id: 'b/mini',
    label: 'mini',
    group: SelectOptionGroup(name: 'b', label: 'Local'),
    detail: 'small model',
  ),
  SelectOption(id: 'free', label: 'Ungrouped'),
];

void main() {
  late List<TokenSegment> consumed;
  late int focused;
  late PopupSelectController popup;
  late List<String> selected;
  late Completer<List<SelectOption>> load;
  late Object? selectError;
  late Completer<void>? selectGate;

  PopupSelectSpec spec({PopupSearchMode mode = PopupSearchMode.substring}) =>
      PopupSelectSpec(
        searchMode: mode,
        options: (id, signal) => load.future,
        onSelect: (o, id) async {
          selected.add(o.id);
          if (selectGate != null) await selectGate!.future;
          if (selectError != null) throw selectError!;
        },
      );

  setUp(() {
    consumed = [];
    focused = 0;
    selected = [];
    load = Completer();
    selectError = null;
    selectGate = null;
    popup = PopupSelectController(
      consume: (s) {
        consumed.add(s);
        return true;
      },
      focusComposer: () => focused++,
    );
  });

  PopupState state() => popup.state.value;

  Future<void> open({PopupSearchMode mode = PopupSearchMode.substring}) async {
    if (load.isCompleted) load = Completer();
    popup.open(
      'model',
      spec(mode: mode),
      's1',
      MenuSegment(TokenSpan(0, 6, 4)),
    );
    load.complete(options);
    await tick();
    await tick();
  }

  group('loading', () {
    test(
      'opens pending and parks the highlight on the row marked active',
      () async {
        popup.open('model', spec(), 's1', EnterSegment('/model'));
        expect(state().open, isTrue);
        expect(state().status, PopupStatus.pending);
        load.complete(options);
        await tick();
        await tick();
        expect(state().status, PopupStatus.ready);
        // The grouped order is shown: Account rows, Local, then the ungrouped block.
        expect(state().active, 0);
        expect(filterOptions(state().options, '').map((o) => o.id), [
          'a/flash',
          'a/pro',
          'b/mini',
          'free',
        ]);
      },
    );

    test(
      'a failed load keeps the popup open for retry and the search survives',
      () async {
        popup.open('model', spec(), 's1', EnterSegment('/model'));
        popup.setSearch('pro');
        load.completeError(StateError('catalog failed'));
        await tick();
        await tick();
        expect(state().status, PopupStatus.failed);
        expect(state().error, contains('catalog failed'));
        expect(state().search, 'pro');
        load = Completer();
        popup.retry();
        expect(state().status, PopupStatus.pending);
        load.complete(options);
        await tick();
        await tick();
        expect(state().status, PopupStatus.ready);
        expect(state().error, isNull);
      },
    );

    test('a superseding open drops the late result of the first', () async {
      final first = load;
      popup.open('model', spec(), 's1', EnterSegment('/model'));
      load = Completer();
      popup.open('permission', spec(), 's1', EnterSegment('/permission'));
      first.complete(const [SelectOption(id: 'stale', label: 'stale')]);
      await tick();
      await tick();
      expect(state().command, 'permission');
      expect(state().options, isEmpty);
    });
  });

  group('searching', () {
    test('substring search matches label and detail and rebases the highlight to the top', () async {
      await open();
      popup.move(1);
      expect(state().active, 1);
      popup.setSearch('SMALL');
      expect(state().active, 0);
      expect(filterOptions(state().options, 'SMALL').map((o) => o.id), [
        'b/mini',
      ]);
      expect(filterOptions(state().options, '  ').length, 4);
    });

    test(
      'fuzzy-label search ranks within each group and ignores the detail',
      () async {
        await open(mode: PopupSearchMode.fuzzyLabel);
        expect(
          filterOptions(
            state().options,
            'pro',
            PopupSearchMode.fuzzyLabel,
          ).map((o) => o.id),
          ['a/pro'],
        );
        expect(
          filterOptions(state().options, 'small', PopupSearchMode.fuzzyLabel),
          isEmpty,
        );
        expect(
          filterOptions(
            state().options,
            'dfl',
            PopupSearchMode.fuzzyLabel,
          ).map((o) => o.id),
          ['a/flash'],
        );
      },
    );

    test('moving wraps over the filtered rows only', () async {
      await open();
      popup.setSearch('deepseek');
      popup.move(-1);
      expect(state().active, 1);
      popup.move(1);
      expect(state().active, 0);
      popup.highlight(1);
      expect(state().active, 1);
      popup.highlight(9);
      expect(state().active, 1);
    });
  });

  group('selecting', () {
    test(
      'success consumes the open-time segment, closes and returns the keyboard',
      () async {
        await open();
        await popup.select(1);
        expect(selected, ['a/pro']);
        expect(consumed.single, isA<MenuSegment>());
        expect(state().open, isFalse);
        expect(focused, 1);
      },
    );

    test(
      'a failure keeps the popup, its search and highlight and names the error',
      () async {
        await open();
        popup.setSearch('mini');
        selectError = StateError('writer held');
        await popup.select(0);
        expect(state().open, isTrue);
        expect(state().submitting, isFalse);
        expect(state().error, contains('writer held'));
        expect(state().search, 'mini');
        expect(consumed, isEmpty);
        // Select re-arms as the retry.
        selectError = null;
        await popup.select(0);
        expect(state().open, isFalse);
        expect(selected, ['b/mini', 'b/mini']);
      },
    );

    test('selection is single-flight', () async {
      await open();
      selectGate = Completer();
      final first = popup.select(0);
      await tick();
      expect(state().submitting, isTrue);
      await popup.select(1);
      popup.setSearch('x');
      popup.move(1);
      selectGate!.complete();
      await first;
      expect(selected, ['a/flash']);
    });

    test(
      'dismissing while onSelect flies revokes its rights: nothing is consumed',
      () async {
        await open();
        selectGate = Completer();
        final flying = popup.select(0);
        await tick();
        popup.dismiss();
        selectGate!.complete();
        await flying;
        expect(consumed, isEmpty);
        expect(focused, 0);
      },
    );

    test(
      'Escape dismisses with the composer focused, an outside press without',
      () async {
        await open();
        popup.dismiss();
        expect(focused, 0);
        await open();
        popup.dismiss(focus: true);
        expect(focused, 1);
        expect(state().open, isFalse);
      },
    );

    test('an out-of-range index selects nothing', () async {
      await open();
      await popup.select(99);
      expect(selected, isEmpty);
      expect(state().open, isTrue);
    });
  });

  group('risk confirmation', () {
    const risky = SelectOption(
      id: 'danger',
      label: 'Full access',
      confirmation: SelectConfirmation(
        title: 't',
        description: 'd',
        acknowledgeLabel: 'a',
        cancelLabel: 'c',
        confirmLabel: 'ok',
      ),
    );

    Future<void> openRisky() async {
      popup.open('permission', spec(), 's1', EnterSegment('/permission'));
      load.complete(const [risky]);
      await tick();
      await tick();
    }

    test(
      'a gated row waits for the acknowledgement and never runs before it',
      () async {
        await openRisky();
        await popup.select(0);
        expect(state().confirming?.id, 'danger');
        expect(selected, isEmpty);
        await popup.confirm();
        expect(selected, isEmpty); // not acknowledged
        popup.acknowledge(true);
        await popup.confirm();
        expect(selected, ['danger']);
        expect(state().open, isFalse);
      },
    );

    test('cancelling returns to the picker, still open', () async {
      await openRisky();
      await popup.select(0);
      popup.cancelConfirmation();
      expect(state().confirming, isNull);
      expect(state().open, isTrue);
      expect(selected, isEmpty);
    });

    test('while the gate is up search and moves are inert', () async {
      await openRisky();
      await popup.select(0);
      popup.setSearch('x');
      expect(state().search, '');
    });
  });
}
