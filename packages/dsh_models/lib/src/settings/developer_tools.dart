import '../observable.dart';
import 'config_form.dart';

/// Host accepted enablement is the single authority for coding surfaces.
class DeveloperToolsPreference {
  final enabled = Observable(false);
  ConfigForm? _host;
  void Function()? _off;
  void bind(ConfigForm? form) {
    _off?.call();
    _host = form;
    void adopt() {
      enabled.set(form?.snapshot.value?['enabled'] == true);
    }

    _off = form?.subscribe(adopt);
    adopt();
  }

  Future<bool> setEnabled(bool value) async =>
      await _host?.set('enabled', value) ?? false;
  Future<void> dispose() async {
    _off?.call();
    await enabled.dispose();
  }
}
