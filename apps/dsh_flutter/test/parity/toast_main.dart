// Synthetic controls drive real Toast primitives and all three migrated owners.
// Preparation only: source-controlled native replay belongs to the final root.
import 'dart:async';
import 'dart:io';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_feature_open_in_app/dsh_feature_open_in_app.dart';
import 'package:dsh_feature_open_in_app/src/file_route_action.dart';
import 'package:dsh_feature_settings/dsh_feature_settings.dart';
import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_flutter/src/platform/window_chrome.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart' show testSessionOwner;
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'helpers/toast_fixture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadPinnedFontsFromEnvironment();
  await WindowChrome.init();
  final dark =
      const bool.fromEnvironment('PARITY_DARK') ||
      Platform.environment['WHALEE_PLATFORM_BRIGHTNESS'] == 'dark';
  runApp(ToastNativeApp(brightness: dark ? Brightness.dark : Brightness.light));
}

class ToastNativeApp extends StatefulWidget {
  const ToastNativeApp({super.key, required this.brightness});
  final Brightness brightness;
  @override
  State<ToastNativeApp> createState() => ToastNativeState();
}

class ToastNativeState extends State<ToastNativeApp> {
  final navigator = GlobalKey<NavigatorState>();
  final focus = FocusNode(debugLabel: 'Toast background action');
  final slots = SlotRegistry();
  final i18n = const DshI18n(DshLocale.en);
  late final session = testSessionOwner(
    'native-toast',
    cwdReader: () => '/synthetic/workspace',
  );
  late final openClient = _OpenClient(_changed);
  late final open = OpenInAppController(
    client: openClient,
    readChoice: () => null,
    writeChoice: (_) {},
  );
  late final services = _OpenServices(open, navigator);
  late final files = DeliverablesModel(_FileClient());
  late final form = _UploadForm(_changed);
  late final upload = AcceptedToggle(form);
  late void Function() off;
  String? direct;
  String lifecycleText = 'Lifecycle original';
  Duration? lifecycleHold;
  var directGeneration = 0,
      ownerGeneration = 0,
      done = 0,
      clicks = 0,
      fileRequests = 0;
  bool reduced = true, fileMounted = true;

  @override
  void initState() {
    super.initState();
    for (final slot in DshSlots.all) {
      slots.declare(slot);
    }
    off = registerOpenInAppFeature(slots, services: services);
    open.setEnabled(true);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void clear() {
    if (navigator.currentState?.canPop() ?? false) {
      navigator.currentState!.pop();
    }
    off();
    off = registerOpenInAppFeature(slots, services: services);
    upload.dismiss();
    setState(() {
      direct = null;
      ownerGeneration++;
      fileMounted = true;
    });
  }

  void show(String id) {
    clear();
    setState(() {
      direct = id;
      directGeneration++;
    });
  }

  void lifecycle() {
    clear();
    setState(() {
      lifecycleText = 'Lifecycle original';
      lifecycleHold = null;
      direct = 'lifecycle';
      directGeneration++;
      done = 0;
    });
  }

  void sameHold() => setState(() => lifecycleText = 'Lifecycle updated');
  void removeFileOwner() => setState(() => fileMounted = false);
  void changedHold() => setState(() {
    lifecycleText = 'Lifecycle changed hold';
    lifecycleHold = dshToastHold + dshToastFade;
  });

  void _complete() {
    if (mounted) {
      setState(() {
        done++;
        direct = null;
      });
    }
  }

  Future<void> saveUpload(bool accepted) async {
    form.refuse = !accepted;
    await upload.set(form.snapshot.value?['enabled'] != true);
    _changed();
  }

  void lightbox(bool toastFirst) {
    clear();
    void toast() => setState(() {
      direct = 'warning';
      directGeneration++;
    });
    void preview() {
      showDshLightbox(
        navigator.currentContext!,
        images: [
          DshLightboxImage(label: 'Synthetic preview', bytes: Uint8List(0)),
        ],
        labels: const DshLightboxLabels(
          dialog: 'Synthetic lightbox',
          close: 'Close preview',
          loadFailed: 'Synthetic preview has no image',
          position: _position,
        ),
      );
    }

    if (toastFirst) {
      toast();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) preview();
      });
    } else {
      preview();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) toast();
      });
    }
  }

  @override
  void dispose() {
    off();
    open.dispose();
    focus.dispose();
    unawaited(files.dispose());
    unawaited(upload.dispose());
    unawaited(session.conversation.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = resolveTheme(
      officialPack,
      ThemeSettings(),
      widget.brightness,
    );
    final fileOwner = DeliverablesFileActionsOwner(
      session: session,
      actionUrl: 'synthetic-toast-file',
      available: true,
      pending: false,
      acquireApplications: () =>
          files.acquireApplications(const DeliveryFile('native-toast', 1, 0)),
      releaseApplications: files.releaseApplications,
      onAction: (action, [application]) async {
        setState(() => fileRequests++);
        return NativeOpenFailure.revealError;
      },
    );
    Widget control(String label, VoidCallback callback) => DshButton(
      key: ValueKey('toast-control-$label'),
      size: DshButtonSize.sm,
      semanticLabel: label,
      onPressed: callback,
      child: Text(label),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f1): clear,
        const SingleActivator(LogicalKeyboardKey.f2): () => show('no-icon'),
        const SingleActivator(LogicalKeyboardKey.f3): () => show('success'),
        const SingleActivator(LogicalKeyboardKey.f4): () => show('warning'),
        const SingleActivator(LogicalKeyboardKey.f5): () =>
            show('long-warning'),
        const SingleActivator(LogicalKeyboardKey.f6): lifecycle,
        const SingleActivator(LogicalKeyboardKey.f7): sameHold,
        const SingleActivator(LogicalKeyboardKey.f8): changedHold,
        const SingleActivator(LogicalKeyboardKey.f9): () => lightbox(true),
        const SingleActivator(LogicalKeyboardKey.f10): () => lightbox(false),
        const SingleActivator(LogicalKeyboardKey.f11): () =>
            setState(() => reduced = !reduced),
        const SingleActivator(LogicalKeyboardKey.f12): focus.requestFocus,
      },
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: navigator,
        theme: ThemeData(brightness: widget.brightness, extensions: [theme]),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: DshToastHost(child: child!),
        ),
        home: Scaffold(
          backgroundColor: theme.bgBase,
          body: DefaultTextStyle(
            style: theme
                .textStyle('--dsw-font-xs-13')
                .copyWith(color: theme.labelPrimary),
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'Toast fixture viewport',
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    top: DshToastRecipe.top,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: DshButton(
                        key: const ValueKey('toast-underlying'),
                        focusNode: focus,
                        semanticLabel: 'Underlying action',
                        onPressed: () => setState(() => clicks++),
                        child: const Text('Underlying action'),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    top:
                        DshToastRecipe.top +
                        DshToastRecipe.lineHeight +
                        DshToastRecipe.verticalPadding * 2 +
                        DshSpace.lg,
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(DshSpace.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Toast fixture: ${direct ?? 'none'}; done: $done; clicks: $clicks',
                              key: const ValueKey('toast-status'),
                            ),
                            Text(
                              'Owner requests: workspace ${openClient.attempts}; file $fileRequests; upload ${form.attempts}',
                              key: const ValueKey('toast-owners'),
                            ),
                            Text(
                              'Reduced motion: ${reduced ? 'on' : 'off'}; upload accepted: ${form.snapshot.value?['enabled']}',
                            ),
                            const Text(
                              'Services: synthetic offline; no network',
                            ),
                            ExcludeFocus(
                              child: Wrap(
                                spacing: DshSpace.xs,
                                runSpacing: DshSpace.xs,
                                children: [
                                  control('Clear', clear),
                                  control('No icon', () => show('no-icon')),
                                  control('Success', () => show('success')),
                                  control('Warning', () => show('warning')),
                                  control('Long', () => show('long-warning')),
                                  control('Lifetime', lifecycle),
                                  control('Same hold', sameHold),
                                  control('Changed hold', changedHold),
                                  control(
                                    'Toast then preview',
                                    () => lightbox(true),
                                  ),
                                  control(
                                    'Preview then toast',
                                    () => lightbox(false),
                                  ),
                                  control(
                                    'Reduced motion',
                                    () => setState(() => reduced = !reduced),
                                  ),
                                  control(
                                    'Focus background',
                                    focus.requestFocus,
                                  ),
                                  control(
                                    'Upload saved',
                                    () => unawaited(saveUpload(true)),
                                  ),
                                  control(
                                    'Upload failed',
                                    () => unawaited(saveUpload(false)),
                                  ),
                                  control('Remove file owner', removeFileOwner),
                                ],
                              ),
                            ),
                            KeyedSubtree(
                              key: ValueKey(ownerGeneration),
                              child: Column(
                                children: [
                                  const Text('Actual workspace owner'),
                                  ...slots.renderList(
                                    DshSlots.conversationSessionHeaderUtilities
                                        .typed<SessionOwner, Widget>(),
                                    session,
                                  ),
                                  const Text('Actual file owner'),
                                  if (fileMounted)
                                    FileRouteAction(
                                      owner: fileOwner,
                                      i18n: i18n,
                                    ),
                                  SettingsUploadNotice(
                                    controller: upload,
                                    i18n: i18n,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (direct != null)
                    direct == 'lifecycle'
                        ? DshToast(
                            key: ValueKey(directGeneration),
                            text: lifecycleText,
                            hold: lifecycleHold,
                            onDone: _complete,
                          )
                        : KeyedSubtree(
                            key: ValueKey(directGeneration),
                            child: toastFixtureWidget(
                              direct!,
                              'en',
                              hold: Duration(
                                milliseconds:
                                    toastFixtureData['stableHoldMs'] as int,
                              ),
                              onDone: _complete,
                            ),
                          ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _position(int index, int total) => '${index + 1} / $total';

class _OpenServices implements OpenInAppServices {
  _OpenServices(this.controller, this.navigatorKey);
  @override
  final OpenInAppController controller;
  @override
  final GlobalKey<NavigatorState> navigatorKey;
  @override
  DshI18n get i18n => const DshI18n(DshLocale.en);
  @override
  ShortcutService? get shortcuts => null;
  @override
  String? currentDirectory() => '/synthetic/workspace';
}

class _OpenClient implements OpenInAppClient {
  _OpenClient(this.changed);
  final VoidCallback changed;
  int attempts = 0;
  @override
  Future<List<String>> apps() async => ['vscode'];
  @override
  Future<Uint8List?> icon(String app) async => null;
  @override
  Future<void> open(String app, String path) async {
    attempts++;
    changed();
    throw StateError('Synthetic launch refusal');
  }
}

class _FileClient implements DeliverablesClient {
  @override
  Future<List<NativeFileApplication>> applications(
    DeliveryFile file, {
    DeliverablesCancel? cancel,
  }) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Only offline application lookup is available');
}

class _UploadForm implements ConfigForm {
  _UploadForm(this.changed);
  final VoidCallback changed;
  bool refuse = false;
  int attempts = 0;
  ConfigFormSnapshot _value = const ConfigFormSnapshot(
    status: ConfigFormStatus.ready,
    value: {'enabled': false},
    base: {'enabled': false},
    user: {},
    writable: true,
    revision: 1,
  );
  final listeners = <VoidCallback>[];
  @override
  ConfigFormSnapshot get snapshot => _value;
  @override
  VoidCallback subscribe(VoidCallback callback) {
    listeners.add(callback);
    return () => listeners.remove(callback);
  }

  @override
  Future<bool> set(String field, Object? value) async {
    attempts++;
    if (refuse) {
      changed();
      return false;
    }
    _value = ConfigFormSnapshot(
      status: ConfigFormStatus.ready,
      value: {field: value},
      base: {field: value},
      user: {},
      writable: true,
      revision: _value.revision! + 1,
    );
    for (final callback in List.of(listeners)) {
      callback();
    }
    changed();
    return true;
  }

  @override
  Future<bool> unset(String field) => set(field, null);
  @override
  Future<bool> mutate(List<SettingsOp> operations, {int? expectedRevision}) =>
      throw StateError('Fixture uses only accepted toggle.set');
}
