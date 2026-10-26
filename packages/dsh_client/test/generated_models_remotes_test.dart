import 'package:dsh_client/generated_credentials.dart';
import 'package:dsh_client/generated_llm.dart';
import 'package:dsh_client/src/remote_caller.dart';
import 'package:test/test.dart';

class Caller implements RemoteCaller {
  final calls = <(String, String, Map<String, Object?>)>[];
  final responses = <Object?>[];
  @override
  Future<Object?> call(
    String ns,
    String method,
    Map<String, Object?> args,
  ) async {
    calls.add((ns, method, args));
    return responses.removeAt(0);
  }
}

void main() {
  test('credential reads project only configured/source/writable, writes carry exact reference', () async {
    final c = Caller()
      ..responses.addAll([
        {
          'ROUTE_API_KEY': {
            'configured': true,
            'writable': true,
            'source': 'file',
            'unexpected': 'must-not-project',
          },
        },
        null,
        null,
      ]);
    final remote = CredentialsRemote(c);
    final facts = await remote.describe(['ROUTE_API_KEY']);
    expect(facts['ROUTE_API_KEY']!.toJson(), {
      'configured': true,
      'source': 'file',
      'writable': true,
    });
    final synthetic = ['synthetic', '-value'].join();
    await remote.set('ROUTE_API_KEY', synthetic);
    await remote.unset('ROUTE_API_KEY');
    expect(c.calls.map((c) => [c.$1, c.$2, c.$3]).toList(), [
      [
        'credentials',
        'describe',
        {
          'refs': ['ROUTE_API_KEY'],
        },
      ],
      [
        'credentials',
        'set',
        {'ref': 'ROUTE_API_KEY', 'value': synthetic},
      ],
      [
        'credentials',
        'unset',
        {'ref': 'ROUTE_API_KEY'},
      ],
    ]);
  });
  test('provider directory and discovery keep wire naming and native auth metadata', () async {
    final c = Caller()
      ..responses.addAll([
        [
          {'id': 'native', 'name': 'Native'},
        ],
        [
          {
            'provider': 'native',
            'displayName': 'Native',
            'settingsNs': 'llm-pi-ai',
            'settingsPath': ['providers', 'native'],
            'declared': false,
            'nativeAuth': {
              'env': ['NATIVE_KEY'],
              'oauth': true,
            },
          },
        ],
        [
          {
            'id': 'model',
            'name': 'Model',
            'contextWindow': 256000,
            'maxTokens': 32000,
            'inputModalities': ['text', 'image'],
          },
        ],
      ]);
    final remote = LlmRemote(c);
    expect((await remote.listProviders()).single.id, 'native');
    expect(
      (await remote.listConfigurableProviders()).single.nativeAuth!.oauth,
      true,
    );
    final models = await remote.discoverModels(
      'llm-pi-ai',
      const LlmModelDiscoveryRequest(
        provider: 'native',
        api: 'openai-completions',
        baseURL: 'https://api.example/v1',
        apiKey: 'synthetic',
      ),
    );
    expect(models.single.inputModalities!.map((m) => m.toJson()), [
      'text',
      'image',
    ]);
    expect([c.calls.last.$1, c.calls.last.$2], ['llm', 'discoverModels']);
    expect(c.calls.last.$3, {
      'settingsNs': 'llm-pi-ai',
      'request': {
        'provider': 'native',
        'baseURL': 'https://api.example/v1',
        'api': 'openai-completions',
        'apiKey': 'synthetic',
      },
    });
    expect(
      () => LlmDiscoveredModel.fromJson({'name': 'without id'}),
      throwsFormatException,
    );
    expect(
      () => CredentialInfo.fromJson({'configured': true}),
      throwsFormatException,
    );
  });
}
