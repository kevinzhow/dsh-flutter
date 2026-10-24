import 'package:dsh_client/dsh_client.dart' show RemoteException;
import 'package:dsh_feature_directory_picker_browse/dsh_feature_directory_picker_browse.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart' show DirectoryFlowOwner;
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart' show DshButton, DshDialogFrame;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_fs.dart';

/// Plays the owner of a directory-flow hole: it opens and withdraws the
/// request and records the one outcome per open.
class Owner extends StatefulWidget {
  const Owner({
    super.key,
    required this.fs,
    required this.log,
    this.locale = DshLocale.en,
    this.open = true,
    this.busy = false,
  });

  final FakeFs fs;
  final List<String> log;
  final DshLocale locale;
  final bool open;
  final bool busy;

  @override
  State<Owner> createState() => OwnerState();
}

class OwnerState extends State<Owner> {
  late bool open = widget.open;
  late bool busy = widget.busy;

  void set({bool? open, bool? busy}) => setState(() {
    this.open = open ?? this.open;
    this.busy = busy ?? this.busy;
  });

  @override
  Widget build(BuildContext context) => BrowseDirectoryFlow(
    owner: DirectoryFlowOwner(
      open: open,
      busy: busy,
      onPicked: (path) {
        widget.log.add('picked:$path');
      },
      onCancel: () {
        widget.log.add('cancel');
        setState(() => open = false);
      },
      onError: (m) => widget.log.add('error:$m'),
    ),
    list: widget.fs.list,
    create: widget.fs.create,
    i18n: DshI18n(widget.locale),
    failureText: directoryFailureText,
  );
}

const wide = Size(1000, 760);
const phone = Size(390, 844);

void main() {
  late FakeFs fs;
  late List<String> log;
  final ownerKey = GlobalKey<OwnerState>();

  setUp(() {
    fs = FakeFs.standard();
    log = [];
  });

  Future<void> pumpOwner(
    WidgetTester t, {
    Size size = wide,
    DshLocale locale = DshLocale.en,
    Brightness brightness = Brightness.light,
    bool open = true,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      dshTestApp(
        Owner(key: ownerKey, fs: fs, log: log, locale: locale, open: open),
        brightness: brightness,
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
  }

  // Every test ends by unmounting, so no timer of the browser outlives it.
  void tw(String name, Future<void> Function(WidgetTester t) body) =>
      testWidgets(name, (t) async {
        await body(t);
        await t.pump(const Duration(seconds: 1));
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
      });

  Finder key(String k) => find.byKey(ValueKey(k));

  group('wide window: the 680 x 500 dialog', () {
    tw(
      'lists the home folder with its crumb, hides dot folders, Open adopts the level',
      (t) async {
        await pumpOwner(t);
        expect(find.text('Select Workspace Directory'), findsOneWidget);
        expect(key('crumb-/home/u'), findsOneWidget);
        expect(find.text('Home'), findsOneWidget);
        expect(find.text('code'), findsOneWidget);
        expect(find.text('docs'), findsOneWidget);
        expect(find.text('.config'), findsNothing);
        final card = t.getRect(find.byKey(const ValueKey('directory-title')));
        expect(card.left, greaterThan(100));
        await t.tap(key('directory-open'));
        await t.pump();
        expect(log, ['picked:/home/u']);
      },
    );

    tw('the card is dsh\'s 680 x 500', (t) async {
      await pumpOwner(t);
      expect(t.getSize(find.byType(DshDialogFrame)), const Size(680, 500));
    });

    tw(
      'a row pick selects it, opens the right column, and Open adopts the folder',
      (t) async {
        await pumpOwner(t);
        await t.tap(key('row-/home/u/code'));
        await t.pump();
        await t.pump();
        expect(find.text('alpha'), findsOneWidget);
        expect(find.text('beta'), findsOneWidget);
        // The level stays on the left beside the preview.
        expect(find.text('docs'), findsOneWidget);
        await t.tap(key('directory-open'));
        await t.pump();
        expect(log, ['picked:/home/u/code']);
      },
    );

    tw('a right-column pick advances one level', (t) async {
      await pumpOwner(t);
      await t.tap(key('row-/home/u/code'));
      await t.pump();
      await t.pump();
      await t.tap(key('row-/home/u/code/alpha'));
      await t.pump();
      await t.pump();
      expect(find.text('docs'), findsNothing);
      expect(find.text('beta'), findsOneWidget);
      expect(find.text('src'), findsOneWidget);
      await t.tap(key('directory-open'));
      await t.pump();
      expect(log, ['picked:/home/u/code/alpha']);
    });

    tw('a crumb walks back, two-pane away from the root', (t) async {
      await pumpOwner(t);
      await t.tap(key('row-/home/u/code'));
      await t.pump();
      await t.pump();
      await t.tap(key('crumb-/home/u'));
      await t.pump(const Duration(milliseconds: 20));
      await t.pump();
      expect(find.text('docs'), findsOneWidget);
    });

    tw('Show hidden files reveals dot folders and seats a check', (t) async {
      await pumpOwner(t);
      expect(find.text('.config'), findsNothing);
      await t.tap(key('directory-show-hidden'));
      await t.pump();
      expect(find.text('.config'), findsOneWidget);
    });

    tw('Cancel is the cancellation', (t) async {
      await pumpOwner(t);
      await t.tap(key('directory-cancel'));
      await t.pump();
      await t.pump();
      expect(log, ['cancel']);
      expect(find.text('Select Workspace Directory'), findsNothing);
    });

    tw('Escape cancels; a scrim tap cancels', (t) async {
      await pumpOwner(t);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      await t.pump();
      expect(log, ['cancel']);
      await t.pumpWidget(const SizedBox());
      log.clear();
      await pumpOwner(t);
      await t.tapAt(const Offset(5, 5));
      await t.pump();
      await t.pump();
      expect(log, ['cancel']);
    });

    tw('the owner withdrawing the request closes it without a second outcome', (
      t,
    ) async {
      await pumpOwner(t);
      ownerKey.currentState!.set(open: false);
      await t.pump();
      await t.pump();
      expect(find.text('Select Workspace Directory'), findsNothing);
      expect(log, isEmpty);
      // And it opens again, fresh at home.
      ownerKey.currentState!.set(open: true);
      await t.pump();
      await t.pump();
      await t.pump();
      expect(find.text('Select Workspace Directory'), findsOneWidget);
      expect(find.text('code'), findsOneWidget);
    });

    tw('an adoption in flight makes every control inert', (t) async {
      await pumpOwner(t);
      ownerKey.currentState!.set(busy: true);
      await t.pump();
      await t.pump();
      await t.tap(key('directory-open'), warnIfMissed: false);
      await t.tap(key('row-/home/u/code'), warnIfMissed: false);
      await t.pump();
      expect(log, isEmpty);
      expect(find.text('alpha'), findsNothing);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(log, isEmpty);
    });

    tw('a listing failure announces itself, the old view stays', (t) async {
      await pumpOwner(t);
      await t.tap(key('directory-edit-zone'));
      await t.pump();
      await t.enterText(key('directory-path-input'), '/missing');
      await t.testTextInput.receiveAction(TextInputAction.go);
      await t.pump();
      await t.pump();
      expect(key('directory-error'), findsOneWidget);
      expect(find.textContaining('unreadable /missing'), findsOneWidget);
    });
  });

  group('path editor', () {
    tw(
      'the pencil opens it seeded, Enter navigates, Escape cancels only the editor',
      (t) async {
        await pumpOwner(t);
        await t.tap(key('directory-edit-zone'));
        await t.pump();
        final input = t.widget<TextField>(key('directory-path-input'));
        expect(input.controller!.text, '/home/u/');
        await t.enterText(key('directory-path-input'), '/home/u/code/');
        await t.testTextInput.receiveAction(TextInputAction.go);
        await t.pump(const Duration(milliseconds: 20));
        await t.pump();
        expect(key('directory-path-input'), findsNothing);
        expect(find.text('alpha'), findsOneWidget);

        await t.tap(key('directory-edit-zone'));
        await t.pump();
        expect(key('directory-path-input'), findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        expect(key('directory-path-input'), findsNothing);
        expect(find.text('Select Workspace Directory'), findsOneWidget);
        expect(log, isEmpty);
      },
    );

    tw('the typed prefix narrows the level; Open and New folder wait', (
      t,
    ) async {
      await pumpOwner(t);
      await t.tap(key('directory-edit-zone'));
      await t.pump();
      await t.enterText(key('directory-path-input'), '/home/u/do');
      await t.pump();
      expect(find.text('docs'), findsOneWidget);
      expect(find.text('code'), findsNothing);
      expect(t.widget<DshButton>(key('directory-open')).onPressed, isNull);
      expect(
        t.widget<DshButton>(key('directory-new-folder')).onPressed,
        isNull,
      );
    });
  });

  group('new folder', () {
    tw('creates under the selection and lands on the new folder', (t) async {
      await pumpOwner(t);
      await t.tap(key('row-/home/u/code'));
      await t.pump();
      await t.pump();
      await t.tap(key('directory-new-folder'));
      await t.pump();
      await t.pump();
      expect(find.text('New folder in "code"'), findsOneWidget);
      await t.enterText(key('directory-folder-name'), 'gamma');
      await t.pump();
      await t.tap(key('directory-create-confirm'));
      await t.pump();
      await t.pump();
      await t.pump();
      await t.pump();
      expect(fs.made, [('/home/u/code', 'gamma')]);
      expect(find.text('New folder in "code"'), findsNothing);
      expect(find.text('gamma'), findsWidgets);
      await t.tap(key('directory-open'));
      await t.pump();
      expect(log, ['picked:/home/u/code/gamma']);
    });

    tw('a refusal stays in the dialog with the Host message', (t) async {
      await pumpOwner(t);
      await t.tap(key('directory-new-folder'));
      await t.pump();
      await t.pump();
      await t.enterText(key('directory-folder-name'), 'exists');
      await t.pump();
      await t.tap(key('directory-create-confirm'));
      await t.pump();
      await t.pump();
      expect(key('directory-create-error'), findsOneWidget);
      expect(find.textContaining('already exists'), findsOneWidget);
      await t.tap(key('directory-create-cancel'));
      await t.pump();
      await t.pump();
      expect(find.text('New folder in "Home"'), findsNothing);
      expect(find.text('Select Workspace Directory'), findsOneWidget);
    });

    tw('Create stays disabled for a blank name', (t) async {
      await pumpOwner(t);
      await t.tap(key('directory-new-folder'));
      await t.pump();
      await t.pump();
      expect(
        t.widget<DshButton>(key('directory-create-confirm')).onPressed,
        isNull,
      );
      await t.enterText(key('directory-folder-name'), '   ');
      await t.pump();
      expect(
        t.widget<DshButton>(key('directory-create-confirm')).onPressed,
        isNull,
      );
      await t.enterText(key('directory-folder-name'), 'x');
      await t.pump();
      expect(
        t.widget<DshButton>(key('directory-create-confirm')).onPressed,
        isNotNull,
      );
    });
  });

  group('a phone gets the same dialog as web', () {
    tw(
      'the card is the room there is: 342 x 500 on a 390 x 844 window, rows 28px',
      (t) async {
        await pumpOwner(t, size: phone);
        final card = t.getRect(find.byType(DshDialogFrame));
        expect(card.width, 342);
        expect(card.height, 500);
        expect(t.getSize(key('row-/home/u/code')).height, 28);
        expect(key('directory-close'), findsNothing);
      },
    );

    tw(
      'two panes of at least 256px scroll sideways with the child pinned into view',
      (t) async {
        await pumpOwner(t, size: phone);
        await t.tap(key('row-/home/u/code'));
        await t.pump();
        await t.pump();
        await t.pump();
        // Both columns exist; the narrow card shows the child pane.
        expect(find.text('alpha'), findsOneWidget);
        expect(find.text('docs'), findsOneWidget);
        expect(t.getSize(key('level-/home/u/code')).width, 256);
        final scroll = t.widget<SingleChildScrollView>(key('directory-miller'));
        expect(scroll.controller!.offset, greaterThan(0));
        expect(t.getRect(find.text('alpha')).left, greaterThan(24));
        expect(t.getRect(find.text('alpha')).right, lessThan(390));
        // Back to the left pane by hand: the level is still there.
        scroll.controller!.jumpTo(0);
        await t.pump();
        expect(t.getRect(find.text('docs')).left, lessThan(100));
      },
    );

    tw(
      'the footer wraps item by item: Cancel and Open fall to their own line, start-aligned',
      (t) async {
        await pumpOwner(t, size: phone);
        final newFolder = t.getRect(key('directory-new-folder'));
        final cancel = t.getRect(key('directory-cancel'));
        final open = t.getRect(key('directory-open'));
        expect(cancel.top, greaterThan(newFolder.bottom));
        expect(cancel.left, newFolder.left);
        expect(open.left, greaterThan(cancel.right));
        expect(open.top, cancel.top);
      },
    );

    tw(
      'on a wide window the footer is one line with Cancel and Open at the far edge',
      (t) async {
        // (zh: the test font is as wide as the em, English labels would not fit)
        await pumpOwner(t, locale: DshLocale.zh);
        final newFolder = t.getRect(key('directory-new-folder'));
        final cancel = t.getRect(key('directory-cancel'));
        final open = t.getRect(key('directory-open'));
        expect(cancel.center.dy, closeTo(newFolder.center.dy, 1));
        expect(open.right, closeTo(500 + 340 - 24, 1));
      },
    );

    tw('New folder is the centered card, above the keyboard', (t) async {
      await pumpOwner(t, size: phone);
      await t.tap(key('directory-new-folder'));
      await t.pump();
      await t.pump();
      expect(find.text('New folder in "Home"'), findsOneWidget);
      final card = t.getRect(find.byKey(const ValueKey('directory-create-in')));
      expect(card.center.dx, closeTo(195, 40));
      expect(card.top, greaterThan(200));
      expect(card.top, lessThan(500));
    });
  });

  group('zh', () {
    tw('the dialog speaks Chinese with dsh\'s own strings', (t) async {
      await pumpOwner(t, locale: DshLocale.zh);
      expect(find.text('选择工作区目录'), findsOneWidget);
      expect(find.text('主目录'), findsOneWidget);
      expect(find.text('新建文件夹'), findsOneWidget);
      expect(find.text('显示隐藏文件'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('打开'), findsOneWidget);
    });
  });

  test('directoryFailureText prefers the Host business message', () {
    expect(
      directoryFailureText(RemoteException('x/y', 'Permission denied')),
      'Permission denied',
    );
    expect(directoryFailureText(StateError('boom')), contains('boom'));
  });
}
