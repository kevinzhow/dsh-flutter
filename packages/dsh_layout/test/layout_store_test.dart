/// The layout store and `ctx.layout` controller (dsh `layout-store.client.spec.ts`,
/// `service.client.spec.ts`).
library;

import 'package:dsh_layout/dsh_layout.dart';
import 'package:test/test.dart';

LayoutStore store([double width = 1920]) => LayoutStore(viewportWidth: width);

void main() {
  group('createLayoutStore', () {
    test('starts with the default sidebar and no right panel preference', () {
      final s = store();
      expect(s.snapshot.panelInfo, const PanelInfo());
      expect(s.layoutInfo, const LayoutInfo(sidebar: 280, viewportWidth: 1920));
      expect(s.layoutInfo.rightbar, isNull);
    });

    test('creates independent instances', () {
      final a = store();
      final b = store();
      a.setSidebar(400);
      a.openRightbar(true, false);
      expect(b.layoutInfo.sidebar, 280);
      expect(b.layoutInfo.rightbar, isNull);
    });

    test('clamps the sidebar to 264-420px', () {
      final s = store();
      s.setSidebar(1);
      expect(s.layoutInfo.sidebar, 264);
      s.setSidebar(9999);
      expect(s.layoutInfo.sidebar, 420);
    });

    test('toggles the wide sidebar between closed and default width', () {
      final s = store();
      s.setSidebar(400);
      s.toggleSidebar();
      expect(s.layoutInfo.sidebar, 0);
      s.toggleSidebar();
      expect(s.layoutInfo.sidebar, 280);
    });

    test('keeps the sidebar preference while toggling its narrow override', () {
      final s = store();
      s.setSidebar(400);
      s.setViewportWidth(980);
      s.toggleSidebar();
      expect(
        (
          s.layoutInfo.sidebar,
          s.layoutInfo.viewportWidth,
          s.layoutInfo.narrowExpanded,
        ),
        (400.0, 980.0, true),
      );
      s.toggleSidebar();
      expect(
        (s.layoutInfo.sidebar, s.layoutInfo.narrowExpanded),
        (400.0, false),
      );
    });

    test('clears the manual override only when crossing 1024px', () {
      final s = store();
      s.setViewportWidth(980);
      s.toggleSidebar();
      s.setViewportWidth(980);
      s.setViewportWidth(1023);
      expect(s.layoutInfo.narrowExpanded, isTrue);
      s.setViewportWidth(1024);
      expect(s.layoutInfo.narrowExpanded, isFalse);
      s.setViewportWidth(980);
      expect(s.layoutInfo.narrowExpanded, isFalse);
    });

    test('notifies on a change and not on a repeat', () {
      final s = store();
      var calls = 0;
      final off = s.subscribe(() => calls++);
      s.setSidebar(400);
      s.setSidebar(400);
      expect(calls, 1);
      off();
      s.setSidebar(300);
      expect(calls, 1);
    });
  });

  group('main panel selection', () {
    test('changes only panelInfo when switching panels and returning to the Conversation', () {
      final s = store();
      s.setSidebar(400);
      s.openRightbar(true, true);
      s.closeRightbar();
      final layoutInfo = s.layoutInfo;
      for (final id in ['panel-a', 'panel-b', null]) {
        final previous = s.panelInfo;
        s.selectPanel(id);
        expect(s.panelInfo, PanelInfo(activePanelId: id));
        expect(identical(s.panelInfo, previous), isFalse);
        expect(identical(s.layoutInfo, layoutInfo), isTrue);
      }
    });

    test(
      'keeps the complete snapshot when selecting the current panel again',
      () {
        final s = store();
        s.selectPanel('panel-a');
        final selected = s.snapshot;
        s.selectPanel('panel-a');
        expect(identical(s.snapshot, selected), isTrue);
        expect(s.panelInfo.activePanelId, 'panel-a');
      },
    );

    test('returns to the Conversation only when the selected main registration disappears', () {
      final s = store();
      final initial = s.snapshot;
      s.retainMainPanels(const []);
      expect(identical(s.snapshot, initial), isTrue);
      s.selectPanel('panel-a');
      final selected = s.snapshot;
      s.retainMainPanels(['conversation', 'panel-a', 'panel-b']);
      expect(identical(s.snapshot, selected), isTrue);
      s.retainMainPanels(['conversation', 'panel-b']);
      expect(s.panelInfo, const PanelInfo());
      expect(identical(s.layoutInfo, selected.layoutInfo), isTrue);
    });

    for (final action in [
      'setSidebar',
      'toggleSidebar',
      'setViewportWidth',
      'setRightbar',
      'openRightbar',
      'closeRightbar',
    ]) {
      test('preserves panelInfo identity when $action changes layoutInfo', () {
        final s = store();
        s.selectPanel('panel-a');
        if (action == 'closeRightbar') s.openRightbar(true, true);
        final previous = s.snapshot;
        switch (action) {
          case 'setSidebar':
            s.setSidebar(400);
          case 'toggleSidebar':
            s.toggleSidebar();
          case 'setViewportWidth':
            s.setViewportWidth(980);
          case 'setRightbar':
            s.setRightbar(500);
          case 'openRightbar':
            s.openRightbar(true, true);
          case 'closeRightbar':
            s.closeRightbar();
        }
        expect(identical(s.panelInfo, previous.panelInfo), isTrue);
        expect(identical(s.layoutInfo, previous.layoutInfo), isFalse);
      });
    }
  });

  group('right panel', () {
    test('initializes at 45% of the latest frame only on first opening', () {
      final s = store();
      s.setViewportWidth(1000);
      expect(s.layoutInfo.rightbar, isNull);
      s.openRightbar(true, false);
      expect(s.layoutInfo.rightbar, 450);
      s.setViewportWidth(2000);
      s.openRightbar(true, true);
      expect(s.layoutInfo.rightbar, 450);
      s.closeRightbar();
      s.openRightbar(true, false);
      expect(s.layoutInfo.rightbar, 450);
    });

    test(
      'keeps track and fullscreen reports independent and clears both on close',
      () {
        final s = store();
        s.openRightbar(true, false);
        expect(
          (
            s.layoutInfo.rightbarShown,
            s.layoutInfo.rightbarTrack,
            s.layoutInfo.rightbarFullscreen,
          ),
          (true, true, false),
        );
        s.openRightbar(true, true);
        expect(
          (
            s.layoutInfo.rightbarShown,
            s.layoutInfo.rightbarTrack,
            s.layoutInfo.rightbarFullscreen,
          ),
          (true, true, true),
        );
        s.openRightbar(false, true);
        expect(
          (
            s.layoutInfo.rightbarShown,
            s.layoutInfo.rightbarTrack,
            s.layoutInfo.rightbarFullscreen,
          ),
          (true, false, true),
        );
        s.closeRightbar();
        expect(
          (
            s.layoutInfo.rightbarShown,
            s.layoutInfo.rightbarTrack,
            s.layoutInfo.rightbarFullscreen,
          ),
          (false, false, false),
        );
      },
    );

    test('keeps dragged px preferences across resize, close, and reopen', () {
      final s = store();
      s.openRightbar(true, false);
      s.setRightbar(1100);
      s.setViewportWidth(800);
      expect(s.layoutInfo.rightbar, 1100);
      s.closeRightbar();
      s.openRightbar(false, true);
      expect(s.layoutInfo.rightbar, 1100);
    });

    test('clamps drag preferences to 300px and 70% of the current frame', () {
      final s = store();
      s.setViewportWidth(1600);
      s.setRightbar(9999);
      expect(s.layoutInfo.rightbar, 1120);
      s.setViewportWidth(1000);
      s.setRightbar(9999);
      expect(s.layoutInfo.rightbar, 700);
      s.setRightbar(1);
      expect(s.layoutInfo.rightbar, 300);
    });

    test('retains a minimum normal preference when first opened fullscreen on a phone', () {
      final s = store();
      s.setViewportWidth(320);
      s.openRightbar(false, true);
      expect(s.layoutInfo.rightbar, 300);
    });

    test('collapses a manually expanded narrow sidebar on opening, not presentation reports', () {
      final s = store();
      s.setSidebar(400);
      s.setViewportWidth(800);
      s.toggleSidebar();
      s.openRightbar(true, false);
      expect(
        (s.layoutInfo.sidebar, s.layoutInfo.narrowExpanded),
        (400.0, false),
      );
      s.toggleSidebar();
      s.openRightbar(true, true);
      expect(s.layoutInfo.narrowExpanded, isTrue);
      s.closeRightbar();
      s.openRightbar(true, false);
      expect(s.layoutInfo.narrowExpanded, isFalse);
    });

    test('keeps the wide sidebar preference and never opens a closed right panel on resize', () {
      final s = store();
      s.setSidebar(420);
      s.openRightbar(true, false);
      expect(s.layoutInfo.sidebar, 420);
      s.closeRightbar();
      s.setViewportWidth(3000);
      expect(
        (
          s.layoutInfo.sidebar,
          s.layoutInfo.rightbarShown,
          s.layoutInfo.rightbarTrack,
        ),
        (420.0, false, false),
      );
    });
  });

  group('right panel instant geometry', () {
    for (final track in [true, false]) {
      test(
        'closes fullscreen with track=$track in one instant update and retains repeated close reports',
        () {
          final s = store();
          s.openRightbar(track, true);
          s.closeRightbar();
          final l = s.layoutInfo;
          expect(
            (
              l.rightbarShown,
              l.rightbarTrack,
              l.rightbarFullscreen,
              l.rightbarInstant,
            ),
            (false, false, false, true),
          );
          final closed = s.snapshot;
          s.closeRightbar();
          expect(identical(s.snapshot, closed), isTrue);
        },
      );
    }

    test('restores the normal track instantly, retaining the marker on an identical report', () {
      final s = store();
      s.openRightbar(true, true);
      s.openRightbar(true, false);
      var l = s.layoutInfo;
      expect(
        (
          l.rightbarShown,
          l.rightbarTrack,
          l.rightbarFullscreen,
          l.rightbarInstant,
        ),
        (true, true, false, true),
      );
      final restored = s.snapshot;
      s.openRightbar(true, false);
      expect(identical(s.snapshot, restored), isTrue);
      s.openRightbar(false, false);
      expect(s.layoutInfo.rightbarInstant, isFalse);
    });

    test('allows a normal close to animate, including after restoring from fullscreen', () {
      final s = store();
      s.openRightbar(true, false);
      s.closeRightbar();
      expect(s.layoutInfo.rightbarInstant, isFalse);
      s.openRightbar(true, true);
      s.openRightbar(true, false);
      expect(s.layoutInfo.rightbarInstant, isTrue);
      s.closeRightbar();
      expect(
        (s.layoutInfo.rightbarTrack, s.layoutInfo.rightbarInstant),
        (false, false),
      );
    });

    for (final action in [
      'setSidebar',
      'toggleSidebar',
      'setRightbar',
      'setViewportWidth',
    ]) {
      test('clears instant geometry on $action', () {
        final s = store();
        s.openRightbar(true, true);
        s.closeRightbar();
        expect(s.layoutInfo.rightbarInstant, isTrue);
        switch (action) {
          case 'toggleSidebar':
            s.toggleSidebar();
          case 'setSidebar':
            s.setSidebar(350);
          case 'setRightbar':
            s.setRightbar(350);
          case 'setViewportWidth':
            s.setViewportWidth(1800);
        }
        expect(s.layoutInfo.rightbarInstant, isFalse);
        s.closeRightbar();
        expect(s.layoutInfo.rightbarInstant, isFalse);
      });
    }

    test('does not let an unchanged frame measurement reset the fullscreen-exit marker', () {
      final s = store();
      s.openRightbar(true, true);
      s.closeRightbar();
      final closed = s.snapshot;
      s.setViewportWidth(closed.layoutInfo.viewportWidth);
      expect(identical(s.snapshot, closed), isTrue);
    });

    for (final fullscreen in [true, false]) {
      test(
        'clears the exit marker on a fresh opening with fullscreen=$fullscreen',
        () {
          final s = store();
          s.openRightbar(true, true);
          s.closeRightbar();
          s.openRightbar(true, fullscreen);
          final l = s.layoutInfo;
          expect(
            (l.rightbarShown, l.rightbarFullscreen, l.rightbarInstant),
            (true, fullscreen, false),
          );
        },
      );
    }
  });

  group('LayoutController', () {
    LayoutController controller(LayoutStore s, [bool Function(String)? has]) =>
        LayoutController(s, has ?? (_) => true);

    test(
      'forwards right column transitions and the sidebar toggle to the store',
      () {
        final s = store();
        final c = controller(s);
        c.openRightbar(true, false);
        expect(
          (s.layoutInfo.rightbarShown, s.layoutInfo.rightbarFullscreen),
          (true, false),
        );
        c.openRightbar(true, true);
        expect(s.layoutInfo.rightbarFullscreen, isTrue);
        c.closeRightbar();
        expect(s.layoutInfo.rightbarShown, isFalse);
        c.toggleSidebar();
        expect(s.layoutInfo.sidebar, 0);
      },
    );

    test('forwards panel selection and returning to the Conversation without changing geometry', () {
      final s = store();
      final c = controller(s);
      final layout = s.layoutInfo;
      c.selectPanel('panel-a');
      c.selectPanel('panel-a');
      expect(c.panelInfo.activePanelId, 'panel-a');
      c.selectPanel(null);
      expect(c.panelInfo.activePanelId, isNull);
      expect(identical(s.layoutInfo, layout), isTrue);
    });

    test(
      'keeps separately constructed controllers bound to their own stores',
      () {
        final first = store();
        final second = store();
        controller(first).toggleSidebar();
        expect(first.layoutInfo.sidebar, 0);
        expect(second.layoutInfo.sidebar, 280);
      },
    );

    test('rejects an absent main entry without changing selection or cancelling pending navigation', () {
      final s = store();
      final present = {'panel-a'};
      final c = controller(s, present.contains);
      c.selectPanel('panel-a');
      final navigation = c.beginNavigation();
      present.remove('panel-a');
      expect(
        () => c.selectPanel('panel-a'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('main panel "panel-a" is not registered'),
          ),
        ),
      );
      expect(s.panelInfo.activePanelId, 'panel-a');
      expect(navigation.aborted, isFalse);
      c.selectPanel(null);
      expect(navigation.aborted, isTrue);
    });

    test('supersedes asynchronous navigation on another request, any valid selection, and disposal', () {
      final c = controller(store());
      final first = c.beginNavigation();
      final second = c.beginNavigation();
      expect(first.aborted, isTrue);
      expect(second.aborted, isFalse);
      c.selectPanel('panel-a');
      expect(second.aborted, isTrue);
      final repeated = c.beginNavigation();
      c.selectPanel('panel-a');
      expect(repeated.aborted, isTrue);
      final pending = c.beginNavigation();
      c.dispose();
      expect(pending.aborted, isTrue);
      c.dispose();
    });
  });
}
