import 'dart:convert';
import 'dart:typed_data';

import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_slots/testing.dart';

Uint8List syntheticPreviewPdf() {
  final out = StringBuffer('%PDF-1.4\n');
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 7 0 R >> >> /Contents 4 0 R >>',
    '',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 7 0 R >> >> /Contents 6 0 R >>',
    '',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  for (final page in [1, 2]) {
    final text =
        'q ${page == 1 ? '0.1 0.5 0.7' : '0.6 0.2 0.5'} rg 40 500 520 150 re f Q\nBT /F1 24 Tf 40 720 Td (Whalee synthetic PDF page $page) Tj ET\nBT /F1 16 Tf 40 450 Td (Two-page authorized native preview.) Tj ET\n';
    objects[page == 1 ? 3 : 5] =
        '<< /Length ${ascii.encode(text).length} >>\nstream\n${text}endstream';
  }
  final offsets = [0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(ascii.encode(out.toString()).length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = ascii.encode(out.toString()).length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(ascii.encode(out.toString()));
}

class SyntheticPluginsPreview {
  SyntheticPluginsPreview() {
    files.root = '/synthetic';
    files.binaries['preview.pdf'] = syntheticPreviewPdf();
    files.binaries['preview.docx'] = Uint8List.fromList([80, 75, 3, 4]);
    files.texts['preview.html'] = '''<!doctype html><html><head><link rel="stylesheet" href="theme.css"></head><body>
<style>body{font:20px sans-serif;padding:24px;background:#f7fafc;color:#18334a}button{font:20px sans-serif;padding:18px;background:#2c6c98;color:white;border:0;border-radius:8px}#status{margin-top:24px;padding:24px;background:#bfe7dd}</style>
<h1>Synthetic HTML</h1><p id="count">Count: 0</p><button id="run">Run script</button><div id="status">Static preview</div>
<script src="counter.js"></script></body></html>''';
    files.texts['theme.css'] = 'h1{border-bottom:8px solid #a52f79}';
    files.texts['counter.js'] = '''let n=0;document.getElementById('run').onclick=()=>{document.getElementById('count').textContent='Count: '+(++n);document.getElementById('status').style.background='#f4c687'};
try{parent.document.body;document.getElementById('status').textContent='Unexpected parent access'}catch(e){document.getElementById('status').textContent='Opaque sandbox: parent blocked'};''';
    host.handlers['officeToPdf/generation'] = (_) => 'synthetic-renderer';
    host.handlers['officeToPdf/render'] = (args) => {
      'absolutePath': '/synthetic/preview.docx',
      'version': 'v1',
      'offset': 0,
      'data': syntheticPreviewPdf(),
      'eof': true,
      'missingFonts': ['Synthetic Missing Font'],
      'generation': 'synthetic-renderer',
    };
    host.handlers['pluginInventory/list'] = (_) => {
      'managementAvailable': true,
      'entries': [
        {
          'entryId': 'synthetic-entry',
          'moduleName': '@synthetic/reader',
          'enabled': enabled,
          'fiberPhase': enabled ? 'active' : null,
        },
      ],
      'agentPresets': [
        {
          'id': 'standard',
          'isDefault': true,
          'rows': [
            {
              'entryId': 'synthetic-preset',
              'moduleName': '@synthetic/preset-reader',
              'enabled': 'conditional',
              'condition': 'synthetic flag',
              'fiberPhase': null,
            },
          ],
        },
      ],
    };
    host.handlers['pluginManager/listBundles'] = (_) => [
      {
        'name': '@synthetic/preview-bundle',
        'official': false,
        'availability': 'profile',
        'installed': true,
        'enabled': enabled,
        'optional': false,
        'removable': true,
        'version': '1.0.0',
        'meta': {
          'title': 'Synthetic preview bundle',
          'description': 'Synthetic package for native interaction checks.',
        },
        'rows': [
          {
            'rowId': 'reader',
            'moduleName': '@synthetic/reader',
            'entryId': 'synthetic-entry',
          },
        ],
        'overrides': <String>[],
      },
    ];
    host.handlers['pluginManager/listPlugins'] = (_) => [
      {
        'entryId': 'synthetic-entry',
        'moduleName': '@synthetic/reader',
        'enabled': enabled,
        'fiberPhase': enabled ? 'active' : null,
        'patchId': 'reader',
      },
    ];
    for (final method in ['setBundleEnabled', 'setPluginEnabled']) {
      host.handlers['pluginManager/$method'] = (args) {
        enabled = args['enabled'] as bool;
        return {
          'changed': true,
          'application': 'applied',
          'stage': 'enable',
          'target': 'synthetic',
        };
      };
    }
    host.handlers['pluginManager/removeBundle'] = (_) => {
      'changed': true,
      'application': 'restart-required',
      'stage': 'remove',
      'target': 'synthetic',
      'restartReason': 'no-hmr',
    };
    host.handlers['pluginManager/registries'] = (_) => {
      'registry': null,
      'resolved': 'https://registry.npmjs.org/',
      'fallbackRegistries': <String>[],
    };
    host.handlers['pluginManager/inspect'] = (args) => {
      'status': 'accepted',
      'kind': 'registry',
      'name': args['spec'],
      'bundle': true,
      'registry': null,
    };
    host.handlers['pluginManager/installBundle'] = (_) async {
      installs++;
      return {
        'changed': true,
        'application': 'applied',
        'stage': 'install',
        'target': 'synthetic',
        'bundle': 'synthetic-added',
        'version': '1.0.0',
      };
    };
    host.handlers['pluginMarket/listIndexes'] = (_) => <Object?>[];
    manager = PluginManagerModel(remotes: host.remotes);
    market = PluginMarketModel(host.remotes);
    office = OfficePreviewService(remotes: host.remotes, files: files);
  }
  final files = FakeWorkspaceFiles();
  final host = FakeHost();
  bool enabled = true;
  int installs = 0;
  late final PluginManagerModel manager;
  late final PluginMarketModel market;
  late final OfficePreviewService office;
  Future<void> dispose() async {
    await manager.dispose();
    await market.dispose();
    await office.dispose();
    await host.close();
  }
}
