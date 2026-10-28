// Profile-region export against immutable published-source frames. This is
// deliberately not a reconstruction of the surrounding PluginManager page.
// With ICON_RASTER_PREPARE=1, replay inputs/geometry without writing captures.
// Final export requires a clean explicit head/tree and a fresh output folder.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dsh_feature_sidebar/dsh_feature_sidebar.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_layout/dsh_layout.dart';
import 'package:dsh_parity/dsh_parity.dart'
    show loadParityFonts, enclosingPixelRect;
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _object(dynamic value) => value as Map<String, dynamic>;
List<dynamic> _list(dynamic value) => value as List<dynamic>;
double _number(dynamic value) => (value as num).toDouble();

Directory _repo() {
  var directory = Directory.current;
  while (!File('${directory.path}/tool/design-system/sources.lock.json')
      .existsSync()) {
    if (directory.parent.path == directory.path) {
      throw StateError('Repository not found');
    }
    directory = directory.parent;
  }
  return directory;
}

String _command(String executable, List<String> args) {
  final result = Process.runSync(executable, args);
  if (result.exitCode != 0) {
    throw StateError('$executable failed: ${result.stderr}');
  }
  return (result.stdout as String).trim();
}

String _hash(File file) =>
    _command('sha256sum', ['--', file.path]).split(RegExp(r'\s+')).first;

Rect _sourceBounds(Map<String, dynamic> snapshot) {
  final bounds = _object(_object(snapshot['actual'])['bounds']);
  return Rect.fromLTWH(
    _number(bounds['x']),
    _number(bounds['y']),
    _number(bounds['width']),
    _number(bounds['height']),
  );
}

const _mouseStates = [
  'idle',
  'hover',
  'held',
  'held-away',
  'held-return',
  'released',
  'pointer-away',
  'home-focus',
  'enter-focus',
];
const _touchStates = [
  'idle',
  'touch-down',
  'touch-up',
  'touch-settled',
  'outside-touch',
  'home-focus',
  'enter-focus',
];

void _validateSource(List<dynamic> traces, Directory source) {
  final files = <String>{};
  for (final raw in traces) {
    final trace = _object(raw), input = trace['input'] as String;
    if (!['mouse', 'touch'].contains(input)) {
      throw StateError('Unknown source input');
    }
    final states = input == 'mouse' ? _mouseStates : _touchStates;
    final snapshots = _list(trace['snapshots']).map(_object).toList();
    final expected = [
      for (final profile in ['iconAction', 'headerAction'])
        for (final state in states) '$profile:$state',
      'iconAction:disabled',
      'iconAction:disabled-after-input',
    ];
    expect([
      for (final s in snapshots) '${s['profile']}:${s['state']}',
    ], expected);
    for (final snapshot in snapshots) {
      final file = snapshot['file'] as String;
      expect(file.contains('/'), isFalse);
      expect(files.add(file), isTrue);
      expect(File('${source.path}/$file').existsSync(), isTrue);
      expect(_sourceBounds(snapshot).size, const Size(28, 28));
    }
  }
}

class _HeaderServices implements SidebarServices {
  _HeaderServices(double width) : store = LayoutStore(viewportWidth: width) {
    layout = LayoutController(store, (_) => false);
    off = store.subscribe(() => toggles++);
  }
  final LayoutStore store;
  late final void Function() off;
  @override
  late final LayoutController layout;
  int toggles = 0, sessions = 0;
  @override
  DshI18n get i18n => const DshI18n(DshLocale.en);
  @override
  String get brandName => 'Whalee';
  @override
  ShortcutService? get shortcuts => null;
  @override
  void startSession() => sessions++;
  @override
  Widget browsingRegion(BuildContext context, SidebarSectionOwner owner) =>
      const SizedBox.shrink();
  void dispose() {
    off();
    layout.dispose();
  }
}

void main() {
  final sourcePath = Platform.environment['ICON_RASTER_SOURCE'];
  if (sourcePath == null) {
    test(
      'published profile raster export is explicitly configured',
      () {},
      skip: 'Set ICON_RASTER_SOURCE and ICON_RASTER_OUT, or ICON_RASTER_PREPARE=1',
    );
    return;
  }
  final source = Directory(sourcePath).absolute;
  final traceFile = File('${source.path}/source-trace.json');
  final sourceData = _object(jsonDecode(traceFile.readAsStringSync()));
  final traces = _list(sourceData['traces']);
  final prepare = Platform.environment['ICON_RASTER_PREPARE'] == '1';
  final outputPath = Platform.environment['ICON_RASTER_OUT'];
  final repo = _repo();

  test('every published snapshot has an explicit supported state mapping', () {
    expect(sourceData['passed'], isTrue);
    _validateSource(traces, source);
  });

  testWidgets('export actual canonical action profiles without pixel fitting', (
    t,
  ) async {
    if (!prepare && outputPath == null) {
      throw StateError('ICON_RASTER_OUT is required');
    }
    final head = _command('git', ['-C', repo.path, 'rev-parse', 'HEAD']);
    final tree = _command('git', ['-C', repo.path, 'rev-parse', 'HEAD^{tree}']);
    if (!prepare) {
      expect(head, Platform.environment['ICON_RASTER_HEAD']);
      expect(tree, Platform.environment['ICON_RASTER_TREE']);
      expect(
        _command('git', ['-C', repo.path, 'status', '--porcelain']),
        isEmpty,
      );
    }
    final out = outputPath == null ? null : Directory(outputPath).absolute;
    if (!prepare) {
      expect(out!.existsSync(), isFalse);
      out.createSync(recursive: true);
    }
    final manifest = File('${repo.path}/tool/parity-fonts/manifest.json');
    await loadParityFonts(manifest.path);
    final rows = <Map<String, dynamic>>[];
    final inputs = <Map<String, dynamic>>[];
    final sourceHashes = <String, String>{};
    final margins = <String, double>{};
    for (final raw in traces) {
      for (final rawSnapshot in _list(_object(raw)['snapshots'])) {
        final snapshot = _object(rawSnapshot),
            actual = _object(snapshot['actual']);
        final profile = snapshot['profile'] as String;
        double px(dynamic value) =>
            double.parse((value as String).replaceFirst('px', ''));
        final reach = px(actual['outlineWidth']) + px(actual['outlineOffset']);
        if (reach > (margins[profile] ?? 0)) margins[profile] = reach;
      }
    }
    for (final raw in traces) {
      final trace = _object(raw),
          snapshots = _list(trace['snapshots']).map(_object).toList();
      final density = _number(trace['density']),
          viewport = _object(trace['viewport']);
      final size = Size(
        _number(viewport['width']),
        _number(viewport['height']),
      );
      final input = trace['input'] as String,
          themeName = trace['theme'] as String;
      final theme = resolveTheme(
        officialPack,
        ThemeSettings(),
        themeName == 'dark' ? Brightness.dark : Brightness.light,
      );
      final iconBounds = _sourceBounds(
        snapshots.firstWhere((s) => s['profile'] == 'iconAction'),
      );
      final headerBounds = _sourceBounds(
        snapshots.firstWhere((s) => s['profile'] == 'headerAction'),
      );
      t.view.devicePixelRatio = density;
      t.view.physicalSize = Size(
        (size.width * density).ceilToDouble(),
        (size.height * density).ceilToDouble(),
      );
      final rootKey = GlobalKey(), iconKey = GlobalKey();
      final iconFocus = FocusNode(), enabled = ValueNotifier(true);
      final services = _HeaderServices(size.width);
      var refresh = 0;
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          themeAnimationDuration: Duration.zero,
          theme: ThemeData(brightness: theme.brightness, extensions: [theme]),
          home: Scaffold(
            backgroundColor: theme.bgBase,
            body: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: rootKey,
                child: SizedBox.fromSize(
                  size: size,
                  child: ColoredBox(
                    color: theme.bgBase,
                    child: DshSurface(
                      color: theme.bgBase,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: iconBounds.left,
                            top: iconBounds.top,
                            child: ValueListenableBuilder<bool>(
                              valueListenable: enabled,
                              builder: (_, active, _) => DshButton(
                                key: iconKey,
                                profile: DshButtonProfile.iconAction,
                                focusNode: iconFocus,
                                semanticLabel: 'refresh',
                                onPressed: active ? () => refresh++ : null,
                                child: const DshIcon(
                                  DshIcons.refresh,
                                  size: DshButtonRecipe.iconSize,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: headerBounds.left,
                            top: headerBounds.top,
                            child: ShellScope(
                              chrome: const ShellChrome(
                                platform: ShellPlatform.darwin,
                              ),
                              child: SidebarLeadingControls(
                                services: services,
                                collapsed: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pump();
      final icon = find.byKey(iconKey),
          header = find.byKey(const ValueKey('leading-toggle'));
      final headerFocus = t
          .widget<FocusableActionDetector>(
            find.descendant(
              of: header,
              matching: find.byType(FocusableActionDetector),
            ),
          )
          .focusNode!;
      final targets = {'iconAction': icon, 'headerAction': header};
      final focuses = {'iconAction': iconFocus, 'headerAction': headerFocus};
      TestGesture? mouse, touch;
      if (input == 'mouse') {
        mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
      }
      String? previousProfile;
      for (final snapshot in snapshots) {
        final profile = snapshot['profile'] as String,
            state = snapshot['state'] as String;
        final target = targets[profile]!, focus = focuses[profile]!;
        if (previousProfile != null && previousProfile != profile) {
          focuses[previousProfile]!.unfocus();
          await t.pump();
        }
        previousProfile = profile;
        final bounds = t.getRect(target), center = bounds.center;
        final outside = Offset(size.width - 20, size.height - 20);
        final performed = <String, dynamic>{
          'theme': themeName,
          'density': density,
          'input': input,
          'profile': profile,
          'state': state,
        };
        switch (state) {
          case 'idle':
            break;
          case 'hover':
            await mouse!.moveTo(center);
          case 'held':
            await mouse!.down(center);
            await t.pump(const Duration(milliseconds: 100));
          case 'held-away':
            await mouse!.moveTo(Offset(bounds.left - 1, center.dy));
          case 'held-return':
            await mouse!.moveTo(center);
          case 'released':
            await mouse!.up();
          case 'pointer-away':
            await mouse!.moveTo(outside);
          case 'touch-down':
            touch = await t.startGesture(center);
            await t.pump(const Duration(milliseconds: 100));
          case 'touch-up':
            await touch!.up();
            touch = null;
          case 'touch-settled':
            await t.pump(const Duration(milliseconds: 500));
          case 'outside-touch':
            await t.tapAt(outside);
          case 'home-focus':
            focus.requestFocus();
            await t.pump();
            await t.sendKeyEvent(LogicalKeyboardKey.home);
          case 'enter-focus':
            await t.sendKeyEvent(LogicalKeyboardKey.enter);
          case 'disabled':
            enabled.value = false;
          case 'disabled-after-input':
            if (input == 'mouse') {
              await mouse!.moveTo(center);
              await mouse.down(center);
              await mouse.up();
            } else {
              await t.tapAt(center);
            }
          default:
            throw StateError('Unmapped source state: $state');
        }
        inputs.add(performed);
        await t.pump(const Duration(milliseconds: 16));
        expect(t.takeException(), isNull);
        final measured = t.getRect(target),
            sourceBounds = _sourceBounds(snapshot);
        expect(measured.size, sourceBounds.size);
        expect(
          (measured.topLeft - sourceBounds.topLeft).distance,
          lessThan(precisionErrorTolerance),
        );
        final filename = snapshot['file'] as String,
            sourceFile = File('${source.path}/$filename');
        sourceHashes[filename] = _hash(sourceFile);
        final roi = enclosingPixelRect(
          sourceBounds.inflate(margins[profile]!),
          density,
        );
        final pending = <String>[];
        if (input == 'touch' && _object(snapshot['actual'])['hover'] == true) {
          pending.add(
            'UNMATCHED/PENDING: Chromium synthetic touch hover is not modeled',
          );
        }
        if (profile == 'headerAction' &&
            ['home-focus', 'enter-focus'].contains(state)) {
          pending.add('UNMATCHED/PENDING: Chromium UA auto-outline paint');
        }
        final calls = {
          'refresh': refresh,
          'toggle': services.toggles,
          'session': services.sessions,
        };
        final sourceCalls = _object(snapshot['calls']);
        final callsMatch = calls.entries.every(
          (e) => sourceCalls[e.key] == e.value,
        );
        if (!callsMatch) {
          pending.add(
            'UNMATCHED/PENDING: source/native callback-effect counts differ',
          );
        }
        final nativeFocused = focus.hasPrimaryFocus;
        final focusOwnershipMatches =
            nativeFocused == _object(snapshot['actual'])['focused'];
        if (!focusOwnershipMatches) {
          pending.add(
            'UNMATCHED/PENDING: source/native pointer focus ownership differs',
          );
        }
        final row = <String, dynamic>{
          ...performed,
          'sourceFile': filename,
          'sourceSha256': sourceHashes[filename],
          'sourceComputed': snapshot['actual'],
          'flutterFile': filename,
          'measuredBounds': [
            measured.left,
            measured.top,
            measured.right,
            measured.bottom,
          ],
          'cropPhysical': [
            roi.left.toInt(),
            roi.top.toInt(),
            roi.right.toInt(),
            roi.bottom.toInt(),
          ],
          'cropReachCss': margins[profile],
          'pending': pending,
          'sourceCalls': sourceCalls,
          'flutterCalls': calls,
          'callbackCountsMatch': callsMatch,
          'flutterFocused': nativeFocused,
          'focusOwnershipMatches': focusOwnershipMatches,
          'flutterFocusRingPresent': find
              .descendant(
                of: target,
                matching: find.byKey(DshButton.focusRingKey),
              )
              .evaluate()
              .isNotEmpty,
          'headerCounterMeaning':
              'actual layout-store transitions from the canonical callback',
          'glyph': profile == 'iconAction'
              ? 'IconRefreshOutlineRegular / DshIcons.refresh'
              : 'IconPanelLeftOutlineRegular / DshShellIcons.panelLeft',
          'scope': 'source-measured profile region; surrounding Web page is not reconstructed',
        };
        final box =
            rootKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final bytes = await t.runAsync(() async {
          final image = await box.toImage(pixelRatio: density);
          row['flutterPhysicalSize'] = [image.width, image.height];
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          return data!.buffer.asUint8List();
        });
        // Exercise encoding during preparation without writing PNG evidence.
        expect(bytes!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        if (!prepare) {
          final file = File('${out!.path}/$filename')..writeAsBytesSync(bytes);
          row['flutterSha256'] = _hash(file);
        }
        rows.add(row);
      }
      await mouse?.removePointer();
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      services.dispose();
      iconFocus.dispose();
      enabled.dispose();
      t.view.reset();
    }
    for (final entry in sourceHashes.entries) {
      expect(_hash(File('${source.path}/${entry.key}')), entry.value);
    }
    final receipt = {
      'schema': 'whalee-icon-action-source-raster/1',
      'mode': prepare ? 'preparation-no-png-export' : 'export',
      'head': head,
      'tree': tree,
      'sourceTraceSha256': _hash(traceFile),
      'sourceProvenanceSha256': _hash(File('${source.path}/provenance.json')),
      'testSha256': _hash(
        File(
          '${repo.path}/apps/dsh_flutter/test/parity/icon_actions_source_raster_test.dart',
        ),
      ),
      'fontManifestSha256': _hash(manifest),
      'sourcePngSha256': sourceHashes,
      'profileCropRule': 'recorded source bounds plus maximum computed outline width+offset for that profile; enclosingPixelRect native rounding',
      'inputs': inputs,
      'frames': rows,
    };
    if (!prepare) {
      expect(_command('git', ['-C', repo.path, 'rev-parse', 'HEAD']), head);
      expect(
        _command('git', ['-C', repo.path, 'rev-parse', 'HEAD^{tree}']),
        tree,
      );
      expect(
        _command('git', ['-C', repo.path, 'status', '--porcelain']),
        isEmpty,
      );
      File('${out!.path}/frames.json')
          .writeAsStringSync('${jsonEncode(receipt)}\n');
    }
    final focusMismatchStates = <String, int>{};
    for (final row in rows.where(
      (row) => row['focusOwnershipMatches'] != true,
    )) {
      final key = '${row['profile']}:${row['input']}:${row['state']}';
      focusMismatchStates.update(key, (value) => value + 1, ifAbsent: () => 1);
    }
    final summary = {
      'mode': receipt['mode'],
      'frames': rows.length,
      'iconAction': rows.where((row) => row['profile'] == 'iconAction').length,
      'headerAction': rows
          .where((row) => row['profile'] == 'headerAction')
          .length,
      'callbackMismatches': rows
          .where((row) => row['callbackCountsMatch'] != true)
          .length,
      'focusOwnershipMismatches': rows
          .where((row) => row['focusOwnershipMatches'] != true)
          .length,
      'focusMismatchStates': focusMismatchStates,
    };
    debugPrint('ICON_SOURCE_RASTER ${jsonEncode(summary)}');
  });
}
