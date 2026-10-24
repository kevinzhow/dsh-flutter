import 'dart:async';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'model_catalog.dart';
import 'model_command.dart';
import 'model_directory.dart';
import 'model_select.dart';

final Slot<SessionOwner, Widget> _seat = DshSlots.conversationInputModel
    .typed<SessionOwner, Widget>();

/// What the feature keeps for the app: the shared catalog and the per-session
/// directories (dsh `ModelDirectoryResolver`).
class ModelSelectionFeature {
  ModelSelectionFeature._(this._remotes, this.catalog);

  void Function()? _off;

  final HostRemotes _remotes;
  final ModelCatalogDirectory catalog;
  final Map<String, ModelDirectory> _directories = {};
  ProjectionStore? Function(String sessionId)? _projectionsOf;

  /// The directory of a session by id (the `/model` popup has no owner): null
  /// when the app holds no projections for it.
  ModelDirectory? directoryOfId(String sessionId) {
    final existing = _directories[sessionId];
    if (existing != null) return existing;
    final projections = _projectionsOf?.call(sessionId);
    if (projections == null) return null;
    return _directories[sessionId] = ModelDirectory(
      remotes: _remotes,
      sessionId: sessionId,
      catalog: catalog,
      projections: projections,
    );
  }

  /// The one directory of [owner]'s session, shared by every entry.
  ModelDirectory directoryFor(SessionOwner owner) => _directories.putIfAbsent(
    owner.sessionId,
    () => ModelDirectory(
      remotes: _remotes,
      sessionId: owner.sessionId,
      catalog: catalog,
      projections: owner.session.projections,
    ),
  );

  /// Drop a closed session's directory.
  Future<void> release(String sessionId) async =>
      _directories.remove(sessionId)?.dispose();

  Future<void> dispose() async {
    _off?.call();
    for (final d in _directories.values) {
      await d.dispose();
    }
    _directories.clear();
    await catalog.dispose();
  }
}

/// Register the model seat into `conversation.input.model` and start the
/// shared catalog read.
///
/// With a [commandUi] registry the `/model` popup joins the `/` menu over the
/// same directories; [projectionsOf] and [isSubagent] tell it about sessions by
/// id.
ModelSelectionFeature registerModelSelectionFeature(
  SlotRegistry slots, {
  required HostRemotes remotes,
  required DshI18n Function() i18n,
  CommandUiRegistry? commandUi,
  ProjectionStore? Function(String sessionId)? projectionsOf,
  bool Function(String sessionId)? isSubagent,
}) {
  final catalog = ModelCatalogDirectory(remotes);
  // The shared catalog loads at start (dsh's resolver does); selectors show
  // its error themselves.
  unawaited(catalog.load().then<void>((_) {}, onError: (Object _) {}));
  final feature = ModelSelectionFeature._(remotes, catalog)
    .._projectionsOf = projectionsOf;
  feature._off = slots.register<SessionOwner, Widget>(
    _seat,
    (owner) => ModelSeat(
      key: ValueKey('model-seat-${owner.sessionId}'),
      directory: feature.directoryFor(owner),
      i18n: i18n(),
    ),
  );
  if (commandUi != null) {
    final off = registerModelCommand(
      commandUi,
      directoryOf: feature.directoryOfId,
      isSubagent: isSubagent ?? (_) => false,
      i18n: i18n,
    );
    final seat = feature._off;
    feature._off = () {
      off();
      seat?.call();
    };
  }
  return feature;
}
