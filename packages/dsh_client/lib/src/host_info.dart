import 'remote_caller.dart';

/// dsh exposes no version handshake on `/api` (no endpoint, no header). The
/// only runtime-readable version is the `version` of an installed bundle in
/// `pluginManager/listBundles`; the `@deepseek-ai/dsh-web-app` bundle is the
/// composition the web carrier serves, so its version is the host version
/// (verified live against 0.2.1-rc.2). A client pins exact versions and
/// refuses unknown ones (docs/upstream-sync.json).
Future<String?> readHostVersion(RemoteCaller caller) async {
  final v = await caller.call('pluginManager', 'listBundles', const {});
  if (v is! List) return null;
  for (final bundle in v) {
    if (bundle is Map<String, Object?> &&
        bundle['name'] == '@deepseek-ai/dsh-web-app') {
      final version = bundle['version'];
      return version is String ? version : null;
    }
  }
  return null;
}
