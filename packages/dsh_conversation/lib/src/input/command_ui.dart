/// The client command surface contract (dsh `ui-commands` `contract.ts`): how
/// a feature adds a slash-menu entry whose behaviour lives on the client (a
/// popup of options, or an action), or decorates what a host command does when
/// invoked bare. `ui-commands` implements the menu and the popup; business
/// features (model selection, permission presets, the composer's File action)
/// register through this registry and never import `ui-commands`.
library;

import 'trigger_types.dart' show AbortSignal;

/// Copy for an option that must be acknowledged before onSelect can run.
class SelectConfirmation {
  const SelectConfirmation({
    required this.title,
    required this.description,
    required this.acknowledgeLabel,
    required this.cancelLabel,
    required this.confirmLabel,
  });
  final String title;
  final String description;
  final String acknowledgeLabel;
  final String cancelLabel;
  final String confirmLabel;
}

/// A caller-owned group name and its localized heading.
class SelectOptionGroup {
  const SelectOptionGroup({required this.name, required this.label});
  final String name;
  final String label;
}

/// How the popup filters its rows.
enum PopupSearchMode { substring, fuzzyLabel }

/// One option row of a popupSelect.
class SelectOption {
  const SelectOption({
    required this.id,
    required this.label,
    this.badge,
    this.detail,
    this.group,
    this.active = false,
    this.confirmation,
  });
  final String id;
  final String label;

  /// A short marker drawn as a superscript beside the label.
  final String? badge;
  final String? detail;

  /// Equal group names share a sticky heading; groups keep first-occurrence
  /// order.
  final SelectOptionGroup? group;

  /// The row the highlight parks on when the panel opens (the session's
  /// current value), so accepting without looking confirms it.
  final bool active;
  final SelectConfirmation? confirmation;
}

/// Command-owned search copy, resolved when the popup opens.
class PopupSearchLabels {
  const PopupSearchLabels({
    required this.placeholder,
    required this.empty,
    required this.noResults,
  });
  final String placeholder;

  /// Empty catalog, before filtering.
  final String empty;

  /// A non-empty catalog with no matching row.
  final String noResults;
}

/// The UI behaviour of a contribution or decoration.
sealed class CommandUiSpec {
  const CommandUiSpec();
}

/// A popup of options; data is self-served by the business feature.
class PopupSelectSpec extends CommandUiSpec {
  const PopupSelectSpec({
    required this.options,
    required this.onSelect,
    this.searchMode = PopupSearchMode.substring,
    this.searchLabels,
  });
  final PopupSearchMode searchMode;
  final PopupSearchLabels Function()? searchLabels;
  final Future<List<SelectOption>> Function(
    String sessionId,
    AbortSignal signal,
  )
  options;
  final Future<void> Function(SelectOption option, String sessionId) onSelect;
}

/// A bare invocation consumes the trigger token and runs one callback. It
/// submits nothing, so an attachment-carrying draft never refuses it.
class ActionSpec extends CommandUiSpec {
  const ActionSpec(this.run);
  final void Function(String sessionId) run;
}

/// A client-owned command: a slash-menu entry with no host descriptor.
class CommandContribution {
  const CommandContribution({
    required this.name,
    required this.available,
    required this.ui,
    this.label,
    this.description,
    this.icon,
  });

  /// The command name without the leading slash (unique).
  final String name;

  /// The localized menu row title; the name when absent. Read on every pass.
  final String Function()? label;
  final String Function()? description;

  /// A glyph key the menu view maps to its icon.
  final String? icon;

  /// A capability filter, called per candidate pass.
  final bool Function(String sessionId) available;
  final CommandUiSpec ui;
}

/// A UI decoration hung on one HOST command: what its bare invocation does on
/// this client. Never manufactures a row; the host command keeps its catalog
/// entry, its argument claim and its lifecycle logging.
class CommandDecoration {
  const CommandDecoration({
    required this.name,
    required this.available,
    required this.ui,
  });
  final String name;
  final bool Function(String sessionId) available;
  final CommandUiSpec ui;
}

/// The `ctx.commandUi` registration face and its state, shared by every feature
/// that contributes a command and the feature that renders the menu.
class CommandUiRegistry {
  final Map<String, CommandContribution> _contributions = {};
  final Map<String, CommandDecoration> _decorations = {};
  final List<void Function(String name)> _dismissals = [];

  Map<String, CommandContribution> get contributions =>
      Map.unmodifiable(_contributions);
  Map<String, CommandDecoration> get decorations =>
      Map.unmodifiable(_decorations);

  /// Register one client command; duplicate names throw. Returns the disposer.
  void Function() register(CommandContribution contribution) {
    if (_contributions.containsKey(contribution.name)) {
      throw StateError('duplicate contribution for /${contribution.name}');
    }
    _contributions[contribution.name] = contribution;
    return () {
      if (identical(_contributions[contribution.name], contribution)) {
        _contributions.remove(contribution.name);
      }
    };
  }

  /// Hang a bare-invocation decoration on one host command; duplicates throw.
  void Function() decorate(CommandDecoration decoration) {
    if (_decorations.containsKey(decoration.name)) {
      throw StateError('duplicate decoration for /${decoration.name}');
    }
    _decorations[decoration.name] = decoration;
    return () {
      if (identical(_decorations[decoration.name], decoration)) {
        _decorations.remove(decoration.name);
      }
    };
  }

  /// Close this command's open popups (its options went stale); drafts stay.
  void dismiss(String name) {
    for (final l in [..._dismissals]) {
      l(name);
    }
  }

  /// Listen for [dismiss] (the popup renderer). Returns the unsubscribe.
  void Function() onDismiss(void Function(String name) listener) {
    _dismissals.add(listener);
    return () => _dismissals.remove(listener);
  }
}
