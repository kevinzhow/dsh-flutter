import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:test/test.dart';

Map<String, Object?> page(int fetchedAt, int count, {int? next}) => {
  'url': 'https://market.example/index.json',
  'title': 'Market',
  'metadata': {
    'categories': <String, Object?>{},
    'labels': <String, Object?>{},
    'sortKeys': <String, Object?>{},
  },
  'fetchedAt': fetchedAt,
  'entries': [
    for (var i = 0; i < count; i++)
      {
        'name': 'package-$fetchedAt-$i',
        'title': 'Package',
        'description': 'Synthetic',
        'metadata': {
          'keywords': <String>[],
          'labels': <String>[],
          'sortKeys': <String, Object?>{},
        },
        'labels': <String>[],
        'keywords': <String>[],
        'versions': [
          {
            'version': '1.0.0',
            'publishTimestamp': 1,
            'engines': <String, Object?>{},
            'source': {'type': 'npm'},
            'compatibility': {'compatible': true},
            'install': {'spec': 'package@1.0.0'},
          },
        ],
        'defaultVersion': '1.0.0',
        'installation': {'status': 'not-installed'},
      },
  ],
  'total': next == null ? count : 200,
  'nextOffset': next,
};
Future<void> tick() => Future<void>.delayed(Duration.zero);
void main() {
  late FakeHost host;
  late PluginMarketModel model;
  setUp(() {
    host = FakeHost();
    host.handlers['pluginMarket/listIndexes'] = (_) => [
      {'url': 'https://market.example/index.json'},
    ];
    model = PluginMarketModel(host.remotes);
  });
  tearDown(() async {
    await model.dispose();
    await host.close();
  });
  test('more pins fetchedAt; replacement restarts once and never joins different documents', () async {
    var reads = 0;
    host.handlers['pluginMarket/search'] = (_) => switch (++reads) {
      1 => page(1, 50, next: 50),
      2 => page(2, 50, next: 100), // more notices replacement
      3 => page(2, 50, next: 50),
      4 => page(3, 50, next: 100), // first replacement within full read
      5 => page(3, 50, next: 50),
      6 => page(4, 50, next: 100), // second replacement fails
      _ => throw StateError('unexpected page'),
    };
    await model.loadIndexes();
    final kept = model.listing!.value;
    await model.more();
    expect(model.listing!.status, PluginListingStatus.error);
    expect(model.listing!.failure, 'changed');
    expect(model.listing!.value, same(kept));
    final calls = host.callsTo('pluginMarket/search');
    expect((calls[1].args['query'] as Map<String, Object?>)['fetchedAt'], 1);
    expect((calls[3].args['query'] as Map<String, Object?>)['fetchedAt'], 2);
    expect((calls[5].args['query'] as Map<String, Object?>)['fetchedAt'], 3);
  });
  test('new search wins over late response; undeclared filters are cleared before settling', () async {
    host.handlers['pluginMarket/search'] = (_) => page(1, 1);
    await model.loadIndexes();
    final slow = Completer<Object?>();
    host.handlers['pluginMarket/search'] = (args) {
      final query = args['query'] as Map<String, Object?>;
      return query['text'] == 'old' ? slow.future : page(2, 1);
    };
    final stale = model.search(const PluginDiscoverQuery(text: 'old'));
    await tick();
    await model.search(
      const PluginDiscoverQuery(
        text: 'new',
        category: 'removed',
        labels: ['removed'],
      ),
    );
    slow.complete(page(3, 1));
    await stale;
    expect(model.listing!.query.text, 'new');
    expect(model.listing!.query.category, isNull);
    expect(model.listing!.query.labels, isEmpty);
    expect(model.listing!.value!.fetchedAt, 2);
    expect(model.listing!.answered, same(model.listing!.query));
  });
  test(
    'source write awaits Host; refusal preserves draft and confirmed list',
    () async {
      host.handlers['pluginMarket/search'] = (_) => page(1, 1);
      await model.loadIndexes();
      final write = Completer<Object?>();
      host.handlers['pluginMarket/setIndexes'] = (_) => write.future;
      model.editDraft('https://other.example/index.json');
      final pending = model.addSource();
      await tick();
      expect(model.saving, isTrue);
      expect(model.indexes, hasLength(1));
      write.completeError(
        RemoteException('plugin-market/invalid-index-url', 'duplicate', {
          'reason': 'duplicate',
        }),
      );
      await pending;
      expect(model.sourceFailure, 'duplicate');
      expect(model.draft, 'https://other.example/index.json');
      expect(model.indexes, hasLength(1));
      host.handlers['pluginMarket/setIndexes'] = (_) => null;
      host.handlers['pluginMarket/listIndexes'] = (_) => [
        {'url': 'https://market.example/index.json'},
        {'url': 'https://other.example/index.json'},
      ];
      await model.addSource();
      expect(model.selected, 'https://other.example/index.json');
      expect(model.draft, isEmpty);
    },
  );
}
