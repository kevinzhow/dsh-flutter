import 'dart:async';

import 'package:dsh_client/generated_directory_picker.dart';
import 'package:dsh_feature_directory_picker_browse/dsh_feature_directory_picker_browse.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_fs.dart';

Future<void> tick([int n = 3]) async {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeFs fs;
  late DirectoryBrowserModel model;

  setUp(() {
    fs = FakeFs.standard();
    model = DirectoryBrowserModel(
      list: fs.list,
      create: fs.create,
      failureText: (e) => e.toString().replaceFirst('Bad state: ', ''),
    );
  });

  tearDown(() => model.dispose());

  BrowserState s() => model.value;

  group('landing', () {
    test(
      'opening lists the Host home as one pane and offers it as the target',
      () async {
        model.open();
        expect(s().loading, isTrue);
        await tick();
        expect(s().loading, isFalse);
        expect(s().parent!.path, '/home/u');
        expect(s().twoPane, isFalse);
        expect(model.openTarget, '/home/u');
        expect(model.canOpen, isTrue);
        expect(displayCrumbs(s().parent!, 'Home').map((c) => c.name), ['Home']);
      },
    );

    test('a crumb jump away from the root lands two-pane: the parent level with the target selected', () async {
      model.open();
      await tick();
      model.navigate('/home/u/code/alpha');
      await tick(6);
      expect(s().parent!.path, '/home/u/code');
      expect(s().selected!.path, '/home/u/code/alpha');
      expect(s().child!.path, '/home/u/code/alpha');
      expect(s().twoPane, isTrue);
      expect(model.openTarget, '/home/u/code/alpha');
    });

    test(
      'a failed listing announces itself and keeps the last readable view',
      () async {
        model.open();
        await tick();
        model.navigate('/nope');
        await tick();
        expect(s().error, contains('unreadable /nope'));
        expect(s().parent!.path, '/home/u');
        expect(s().loading, isFalse);
      },
    );

    test('a failed home listing leaves nothing to open', () async {
      fs.tree.remove('/home/u');
      model.open();
      await tick();
      expect(s().parent, isNull);
      expect(s().error, isNotNull);
      expect(model.canOpen, isFalse);
    });

    test(
      'newer intent aborts the scan in flight and drops its answer',
      () async {
        model.open();
        await tick();
        fs.gates['/home/u/code'] = Completer();
        model.navigate('/home/u/code');
        await tick();
        model.navigate('/home/u/docs');
        await tick(6);
        expect(fs.abortedScans, greaterThan(0));
        fs.gates['/home/u/code']!.complete();
        await tick(6);
        expect(s().crumbSource!.path, '/home/u/docs');
      },
    );

    test(
      'a slow parent leg commits the target alone and upgrades in place',
      () async {
        model.open();
        await tick();
        fs.gates['/home/u/code'] = Completer();
        model.navigate('/home/u/code/alpha');
        await tick();
        await Future<void>.delayed(
          parentLegWait + const Duration(milliseconds: 50),
        );
        expect(s().parent!.path, '/home/u/code/alpha');
        expect(s().twoPane, isFalse);
        fs.gates['/home/u/code']!.complete();
        await tick(6);
        expect(s().twoPane, isTrue);
        expect(s().selected!.name, 'alpha');
      },
    );
  });

  group('picking', () {
    setUp(() async {
      model.open();
      await tick();
    });

    test('a row pick selects at once and previews its children', () async {
      model.select(s().parent!.entries.firstWhere((e) => e.name == 'code'));
      expect(s().selected!.name, 'code');
      expect(s().child, isNull);
      expect(s().loading, isTrue);
      await tick();
      expect(s().child!.path, '/home/u/code');
      expect(s().loading, isFalse);
      expect(model.openTarget, '/home/u/code');
    });

    test(
      'a right-column pick advances one level: the child becomes the level',
      () async {
        model.select(s().parent!.entries.firstWhere((e) => e.name == 'code'));
        await tick();
        model.advance(s().child!.entries.firstWhere((e) => e.name == 'alpha'));
        await tick();
        expect(s().parent!.path, '/home/u/code');
        expect(s().selected!.name, 'alpha');
        expect(s().child!.path, '/home/u/code/alpha');
      },
    );

    test('pick reaches whichever pane the view shows', () async {
      model.pick(s().parent!.entries.firstWhere((e) => e.name == 'code'));
      await tick();
      model.pick(s().child!.entries.firstWhere((e) => e.name == 'beta'));
      await tick();
      expect(s().selected!.name, 'beta');
    });

    test('an unreadable pick falls back to the level and says why', () async {
      model.select(
        const DirectoryEntry(name: 'gone', path: '/home/u/gone', hidden: false),
      );
      await tick();
      expect(s().error, contains('unreadable'));
      expect(s().selected, isNull);
      expect(model.openTarget, '/home/u');
    });
  });

  group('hidden entries', () {
    test('are filtered until revealed, the selection is exempt, a dot prefix names them', () async {
      model.open();
      await tick();
      final all = s().parent!.entries;
      expect(visibleEntries(all, null, false, null).map((e) => e.name), [
        'code',
        'docs',
        'notes',
      ]);
      model.toggleHidden();
      expect(
        visibleEntries(all, null, s().showHidden, null).map((e) => e.name),
        ['code', 'docs', '.config', 'notes'],
      );
      final config = all.firstWhere((e) => e.name == '.config');
      expect(visibleEntries(all, config.path, false, null).map((e) => e.name), [
        'code',
        'docs',
        '.config',
        'notes',
      ]);
      expect(visibleEntries(all, null, false, '.c').map((e) => e.name), [
        '.config',
      ]);
    });

    test('a prefix narrows only while something displayable matches', () {
      final entries = [
        for (final n in ['alpha', 'alto', 'beta']) fs.entry('/x/$n'),
      ];
      expect(visibleEntries(entries, null, false, 'al').map((e) => e.name), [
        'alpha',
        'alto',
      ]);
      expect(visibleEntries(entries, null, false, 'zz').map((e) => e.name), [
        'alpha',
        'alto',
        'beta',
      ]);
      expect(visibleEntries(entries, null, false, 'AL').map((e) => e.name), [
        'alpha',
        'alto',
      ]);
    });
  });

  group('path editor', () {
    setUp(() async {
      model.open();
      await tick();
    });

    test(
      'opens seeded with a trailing separator and Enter navigates',
      () async {
        model.startPathEdit();
        expect(s().pathDraft, '/home/u/');
        model.setPathDraft('/home/u/code/');
        model.submitPath();
        await tick(6);
        expect(s().pathDraft, isNull);
        expect(s().crumbSource!.path, '/home/u/code');
        expect(model.openTarget, '/home/u/code');
      },
    );

    test('a failed submission keeps the editor and reports', () async {
      model.startPathEdit();
      model.setPathDraft('/missing/');
      model.submitPath();
      await tick();
      expect(s().pathDraft, '/missing/');
      expect(s().error, contains('unreadable'));
    });

    test('a blank draft does not submit', () async {
      model.startPathEdit();
      model.setPathDraft('   ');
      model.submitPath();
      await tick();
      expect(fs.listed.where((p) => p.trim().isEmpty), isEmpty);
    });

    test(
      'the final segment prefix-filters the level the draft names',
      () async {
        model.startPathEdit();
        model.setPathDraft('/home/u/co');
        expect(model.typedPrefix, 'co');
        model.setPathDraft('/home/u/');
        expect(model.typedPrefix, '');
        model.setPathDraft('/elsewhere/xyz');
        expect(model.typedPrefix, isNull);
      },
    );

    test('the panes follow the draft to a directory no pane lists after the debounce', () async {
      model.startPathEdit();
      model.setPathDraft('/home/u/code/');
      await Future<void>.delayed(
        draftPreviewDebounce + const Duration(milliseconds: 80),
      );
      await tick(8);
      expect(s().pathDraft, '/home/u/code/'); // the editor stays open
      expect(s().crumbSource!.path, '/home/u/code');
      expect(s().twoPane, isTrue);
    });

    test('one keystroke after another scans once, at rest', () async {
      model.startPathEdit();
      final before = fs.listed.length;
      for (final d in [
        '/home/u/c',
        '/home/u/co',
        '/home/u/code',
        '/home/u/code/',
      ]) {
        model.setPathDraft(d);
      }
      await Future<void>.delayed(
        draftPreviewDebounce + const Duration(milliseconds: 80),
      );
      await tick(8);
      // The target leg and its parent leg: two listings, not one per keystroke.
      expect(fs.listed.length - before, lessThanOrEqualTo(2));
    });

    test('Escape cancels back to the crumbs and keeps a selection only with its preview', () async {
      model.select(s().parent!.entries.firstWhere((e) => e.name == 'code'));
      model.startPathEdit();
      model.cancelPathEdit();
      expect(s().pathDraft, isNull);
      expect(s().selected, isNull);
    });

    test('a pick while editing adopts the row and closes the editor', () async {
      model.startPathEdit();
      model.select(s().parent!.entries.firstWhere((e) => e.name == 'docs'));
      expect(s().pathDraft, isNull);
      await tick();
      expect(model.openTarget, '/home/u/docs');
    });

    test('Open waits for a pending draft', () async {
      model.startPathEdit();
      expect(model.canOpen, isFalse);
      expect(model.canCreate, isFalse);
    });
  });

  group('new folder', () {
    setUp(() async {
      model.open();
      await tick();
    });

    test('creates under the selection, lands on the level and selects the new folder', () async {
      model.select(s().parent!.entries.firstWhere((e) => e.name == 'code'));
      await tick();
      expect(model.targetName, 'code');
      model.startCreate();
      model.setFolderDraft('gamma');
      await model.confirmCreate();
      await tick(6);
      expect(fs.made, [('/home/u/code', 'gamma')]);
      expect(s().folderDraft, isNull);
      expect(s().parent!.path, '/home/u/code');
      expect(s().selected!.name, 'gamma');
      expect(s().child!.path, '/home/u/code/gamma');
      expect(model.openTarget, '/home/u/code/gamma');
    });

    test(
      'with no selection it creates in the listed level, named by its crumb',
      () async {
        expect(model.targetName, 'Home');
        model.startCreate();
        model.setFolderDraft('fresh');
        await model.confirmCreate();
        await tick(6);
        expect(fs.made, [('/home/u', 'fresh')]);
        expect(s().selected!.name, 'fresh');
      },
    );

    test(
      'the Host gets the original spelling; an all-blank name is not sent',
      () async {
        model.startCreate();
        model.setFolderDraft('  ');
        await model.confirmCreate();
        expect(fs.made, isEmpty);
        model.setFolderDraft(' spaced ');
        await model.confirmCreate();
        expect(fs.made.single.$2, ' spaced ');
      },
    );

    test(
      'a refusal names itself in the dialog and keeps it open for another name',
      () async {
        model.startCreate();
        model.setFolderDraft('exists');
        await model.confirmCreate();
        expect(s().createError, 'already exists');
        expect(s().folderDraft, 'exists');
        expect(s().creatingFolder, isFalse);
        model.setFolderDraft('other');
        await model.confirmCreate();
        await tick(6);
        expect(s().folderDraft, isNull);
      },
    );

    test('closing the browser mid-creation drops the late answer', () async {
      model.startCreate();
      model.setFolderDraft('late');
      final pending = model.confirmCreate();
      model.close();
      await pending;
      await tick(6);
      expect(s().parent, isNull);
      expect(s().folderDraft, isNull);
    });

    test('cancel closes the dialog unless a creation is in flight', () {
      model.startCreate();
      model.cancelCreate();
      expect(s().folderDraft, isNull);
    });
  });

  group('lifecycle', () {
    test(
      'reopening starts fresh at home and a closed browser holds nothing',
      () async {
        model.open();
        await tick();
        model.navigate('/home/u/code');
        await tick(6);
        model.close();
        expect(s().parent, isNull);
        model.open();
        await tick();
        expect(s().parent!.path, '/home/u');
        expect(s().showHidden, isFalse);
      },
    );

    test(
      'the loading pill appears only for a scan past the silence window',
      () async {
        model.open();
        await tick();
        fs.gates['/home/u/docs'] = Completer();
        model.navigate('/home/u/docs');
        await tick();
        expect(s().loading, isTrue);
        expect(s().slowScan, isFalse);
        await Future<void>.delayed(
          slowScanDelay + const Duration(milliseconds: 60),
        );
        expect(s().slowScan, isTrue);
        fs.gates['/home/u/docs']!.complete();
        await tick(6);
        expect(s().slowScan, isFalse);
      },
    );
  });
}
