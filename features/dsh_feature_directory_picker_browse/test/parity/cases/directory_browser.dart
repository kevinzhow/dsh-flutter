// The in-app Select Workspace Directory dialog (dsh ui-directory-picker-browse DirectoryBrowser) over the same fixture tree the
// React host lists.
import 'package:dsh_client/generated_directory_picker.dart';
import 'package:dsh_feature_directory_picker_browse/dsh_feature_directory_picker_browse.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

const _home = '/home/u';
const _tree = <String, List<String>>{
  _home: ['Desktop', 'Documents', 'Downloads', 'notes', 'projects', '.config'],
  '$_home/projects': ['atlas', 'harbor', 'meadow', 'orchard'],
  '$_home/projects/atlas': ['docs', 'src'],
  '$_home/projects/empty': [],
};

DirectoryEntry _entry(String path, [bool hidden = false]) =>
    DirectoryEntry(name: path.split('/').last, path: path, hidden: hidden);

DirectoryListing _listing(String path, {bool truncated = false}) {
  final parts = path.split('/').where((p) => p.isNotEmpty).toList();
  return DirectoryListing(
    path: path,
    home: _home,
    crumbs: [
      const DirectoryEntry(name: '/', path: '/', hidden: false),
      for (var i = 0; i < parts.length; i++)
        _entry('/${parts.sublist(0, i + 1).join('/')}'),
    ],
    entries: [
      for (final n in _tree[path] ?? const <String>[])
        _entry('$path/$n', n.startsWith('.')),
    ],
    truncated: truncated,
  );
}

final Map<String, ParityCase> directoryBrowserCases = {
  'workspace.directory': ParityCase(
    widgets: const ['dsh_feature_directory_picker_browse:DirectoryBrowserView'],
    framed: false,
    build: (ctx) {
      final variant = ctx.props['variant'] as String? ?? 'home';
      final model = DirectoryBrowserModel(
        list: (path, signal) async => throw StateError('no host'),
        create: (path, name) async => throw StateError('no host'),
      );
      final BrowserState state = switch (variant) {
        'two-pane' => BrowserState(
          parent: _listing(_home),
          selected: _entry('$_home/projects'),
          child: _listing('$_home/projects'),
        ),
        'empty' => BrowserState(
          parent: _listing('$_home/projects'),
          selected: _entry('$_home/projects/empty'),
          child: _listing('$_home/projects/empty'),
        ),
        'truncated' => BrowserState(parent: _listing(_home, truncated: true)),
        'error' => const BrowserState(error: 'Permission denied'),
        _ => BrowserState(parent: _listing(_home)),
      };
      model.state.set(state);
      // The modal's mask sits over the page: it shows in the card's rounded corners.
      return ColoredBox(
        color: ctx.theme.bgBase,
        child: ColoredBox(
          color: ctx.theme.color('--dsw-alias-bg-mask-1'),
          child: Padding(
            // Modal's root keeps 24px of air on every side.
            padding: const EdgeInsets.all(24),
            child: Align(
              alignment: Alignment.topLeft,
              child: DshDialogFrame(
                key: const ValueKey('directory-dialog'),
                width: 680,
                height: 500,
                child: DirectoryBrowserView(
                  model: model,
                  i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
                  busy: false,
                  onOpen: (_) {},
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );
    },
  ),
};
