// The sidebar terminal panel (dsh ui-sidebar-terminal TerminalBody): status strip, error line, missing-terminal panel and the
// emulator screen, over a scripted fake host.
import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_feature_sidebar_terminal/dsh_feature_sidebar_terminal.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Actions implements SidebarTabActions {
  @override
  void openResource(String address, {int? line}) {}
  @override
  void openTab(
    String kind, {
    String? replaceTabId,
    Map<String, Object?> params = const {},
  }) {}
}

/// The scripted host of the case being captured (one case at a time).
FakeTerminalHost? _fake;

Map<String, Object?> _info(Map<String, dynamic> j) => {
  ...j.cast<String, Object?>(),
};

final Map<String, ParityCase> terminalCases = {
  'terminal.body': ParityCase(
    widgets: const ['dsh_feature_sidebar_terminal:TerminalBody'],
    notes: 'The emulator is xterm (Flutter); dsh web draws xterm.js. Cell grids differ, so the screen region is not pixel-comparable.',
    build: (ctx) {
      final props = ctx.props;
      final state = (props['state'] as Map).cast<String, dynamic>();
      final phase = state['phase'] as String;
      final fake = _fake = FakeTerminalHost();
      fake.host.generation = FakeGeneration();
      if (phase == 'loading') {
        // The environment never answers: the strip says it is reading.
        fake.host.handlers['terminal/environment'] = (_) =>
            Future<Object?>.delayed(const Duration(days: 1));
      }
      if (phase == 'failed' && state['issue'] == 'terminalLimit') {
        fake.host.handlers['terminal/create'] = (_) => throw RemoteException(
          'terminal/limit-reached',
          'limit',
          {'limit': 8},
        );
      } else if (phase == 'failed' && state['error'] != null) {
        fake.host.handlers['terminal/create'] = (_) =>
            throw RemoteException('terminal/failed', '${state['error']}');
      }
      final terminals = ClientTerminals(host: fake.terminalHost);
      final missing = state['issue'] == 'missingTerminal';
      if (missing) {
        terminals.view('s1', 'terminal-1', terminalId: 'gone');
      }
      final owner = SidebarTabOwner(
        session: testSessionOwner('s1'),
        id: 'terminal-1',
        kind: 'terminal',
        contentId: 'sidebar://terminal/1',
        actions: _Actions(),
      );
      final width = (props['width'] as num).toDouble();
      final height = (props['height'] as num).toDouble();
      final locale = DshLocale.fromTag(ctx.locale);
      return Builder(
        builder: (context) {
          // The user's terminal font list is `SF Mono`, which the harness registers on both providers.
          final base = Theme.of(context);
          final settings = ThemeSettings(
            preference: base.brightness == Brightness.dark
                ? ThemePreference.dark
                : ThemePreference.light,
            terminalFontFamily: 'SF Mono',
          );
          final resolved = resolveTheme(
            officialPack,
            settings,
            base.brightness,
          );
          return Theme(
            data: base.copyWith(extensions: [resolved]),
            child: Align(
              alignment: Alignment.topLeft,
              child: parityItem(
                'terminal',
                SizedBox(
                  width: width,
                  height: height,
                  child: TerminalBody(
                    owner: owner,
                    terminals: terminals,
                    i18n: DshI18n(locale),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
    interact: (t, ctx) async {
      final fake = _fake!;
      final state = (ctx.props['state'] as Map).cast<String, dynamic>();
      final phase = state['phase'] as String;
      Future<void> settle() async {
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 20));
        }
      }

      await settle();
      final screen = ctx.props['screen'] as String?;
      final info = state['info'] == null
          ? terminalInfo(id: 'x')
          : _info((state['info'] as Map).cast<String, dynamic>());
      final id = fake.host.callsTo('terminal/create').isEmpty
          ? null
          : (fake.host.callsTo('terminal/create').single.args['request']!
                as Map)['id'];
      final shown = {...info, 'id': id ?? info['id']};
      switch (phase) {
        case 'connecting':
          if (fake.attaches.isNotEmpty) fake.attach.open(1);
        case 'connected' || 'disconnected':
          if (fake.attaches.isNotEmpty) {
            fake.attach.start(
              1,
              terminalSnapshot(
                screen: screen ?? '',
                info: shown,
                writable:
                    state['info']?['state'] != 'exited' &&
                    state['writable'] == true,
              ),
            );
            await settle();
            if (state['info']?['state'] == 'exited') {
              fake.attach.emit(1, terminalState(shown, writable: false));
            }
            if (phase == 'disconnected') {
              fake.attach.end(1, CarrierLost('connection lost'));
            }
          }
      }
      await settle();
    },
  ),
};
