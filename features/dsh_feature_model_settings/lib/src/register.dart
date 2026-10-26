import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'models_section.dart';
import 'welcome.dart';

class ModelSettingsFeature {
  ModelSettingsFeature(this.store, this._off);
  final ModelsSettingsStore store;
  final void Function() _off;
  Future<void> dispose() async {
    _off();
    await store.dispose();
  }
}

ModelSettingsFeature registerModelSettingsFeature(
  SlotRegistry slots, {
  required HostRemotes remotes,
  required ConfigForms forms,
  required DshI18n Function() i18n,
}) {
  final store = ModelsSettingsStore(remotes, forms.mirror);
  final off = slots.register<SettingsOwner, Widget>(
    DshSlots.settingsSection.typed<SettingsOwner, Widget>(),
    (_) => ModelsSection(store: store, i18n: i18n(), slots: slots),
    id: 'models',
    order: 10,
    label: () => i18n().t('settings.models', 'nav'),
  );
  final onboarding = forms.whileServed(
    ['ui-settings-general'],
    (_) => slots.register<SettingsOnboardingOwner, Widget>(
      DshSlots.settingsOnboarding.typed<SettingsOnboardingOwner, Widget>(),
      (owner) => WelcomeNotice(
        form: forms.get('ui-settings-general'),
        owner: owner,
        i18n: i18n(),
      ),
      id: 'welcome-notice',
      order: -100,
    ),
  );
  return ModelSettingsFeature(store, () {
    onboarding();
    off();
  });
}
