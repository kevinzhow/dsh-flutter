import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_models/dsh_models.dart' show Observable;
import 'package:dsh_ui/dsh_ui.dart' show rankByName;

/// The command token segment snapshotted at popup-open time, replayed to the
/// consume callback after a successful selection. The composer guards it: a
/// menu span consumes iff the draft revision is unchanged, an Enter-path line
/// iff the trimmed draft still equals the bare token.
sealed class TokenSegment {
  const TokenSegment();
}

final class MenuSegment extends TokenSegment {
  const MenuSegment(this.span);
  final TokenSpan span;
}

final class EnterSegment extends TokenSegment {
  const EnterSegment(this.token);
  final String token;
}

/// Popup state (the view renders from here; closed renders nothing).
class PopupState {
  const PopupState({
    this.open = false,
    this.command,
    this.status = PopupStatus.pending,
    this.options = const [],
    this.search = '',
    this.searchLabels,
    this.searchMode = PopupSearchMode.substring,
    this.active = 0,
    this.submitting = false,
    this.confirming,
    this.acknowledged = false,
    this.error,
  });

  final bool open;

  /// The command the popup is open for.
  final String? command;
  final PopupStatus status;

  /// The options as loaded; never refetched per keystroke.
  final List<SelectOption> options;
  final String search;
  final PopupSearchLabels? searchLabels;
  final PopupSearchMode searchMode;

  /// Highlight index into the filtered rows: the row the list marks active when
  /// the options land, else 0; a search rebases it to the top.
  final int active;

  /// A selection is in flight: further select, search and highlight no-op.
  final bool submitting;

  /// The option waiting for explicit risk acknowledgement.
  final SelectOption? confirming;
  final bool acknowledged;

  /// A settlement failure (options load or onSelect).
  final String? error;

  PopupState copyWith({
    PopupStatus? status,
    List<SelectOption>? options,
    String? search,
    int? active,
    bool? submitting,
    Object? confirming = _keep,
    bool? acknowledged,
    Object? error = _keep,
  }) => PopupState(
    open: open,
    command: command,
    status: status ?? this.status,
    options: options ?? this.options,
    search: search ?? this.search,
    searchLabels: searchLabels,
    searchMode: searchMode,
    active: active ?? this.active,
    submitting: submitting ?? this.submitting,
    confirming: identical(confirming, _keep)
        ? this.confirming
        : confirming as SelectOption?,
    acknowledged: acknowledged ?? this.acknowledged,
    error: identical(error, _keep) ? this.error : error as String?,
  );

  static const Object _keep = Object();
}

enum PopupStatus { pending, ready, failed }

/// Group rows by their caller-owned group name without sorting groups or rows;
/// ungrouped rows form one block at their first occurrence.
List<({SelectOptionGroup? group, List<SelectOption> rows})> groupOptions(
  List<SelectOption> options,
) {
  final groups =
      <String?, ({SelectOptionGroup? group, List<SelectOption> rows})>{};
  for (final option in options) {
    final name = option.group?.name;
    final existing = groups[name];
    if (existing != null) {
      existing.rows.add(option);
    } else {
      groups[name] = (group: option.group, rows: [option]);
    }
  }
  return groups.values.toList();
}

/// Filter rows by substring (label and detail), or rank labels fuzzily within
/// each group. A blank search keeps every row; the order returned is the order
/// shown and used for selection.
List<SelectOption> filterOptions(
  List<SelectOption> options,
  String search, [
  PopupSearchMode mode = PopupSearchMode.substring,
]) {
  final query = search.trim().toLowerCase();
  final groups = groupOptions(options);
  final ordered = groups.any((g) => g.group != null)
      ? [for (final g in groups) ...g.rows]
      : options;
  if (query.isEmpty) return ordered;
  if (mode == PopupSearchMode.fuzzyLabel) {
    return [
      for (final g in groups)
        ...rankByName<SelectOption>(g.rows, query, name: (o) => o.label),
    ];
  }
  return [
    for (final o in ordered)
      if (o.label.toLowerCase().contains(query) ||
          (o.detail?.toLowerCase().contains(query) ?? false))
        o,
  ];
}

int _currentIndex(
  List<SelectOption> options,
  String search,
  PopupSearchMode mode,
) {
  final at = filterOptions(options, search, mode).indexWhere((o) => o.active);
  return at == -1 ? 0 : at;
}

class _Binding {
  _Binding(this.command, this.spec, this.sessionId, this.segment);
  final String command;
  final PopupSelectSpec spec;
  final String sessionId;
  final TokenSegment segment;
  final AbortController abort = AbortController();
}

/// The headless popupSelect of one session (dsh `PopupSelectController`): a
/// transient layer, never part of the input machine. It loads options once,
/// filters them locally and settles a selection through the session captured at
/// open time. Late settlements lose their write rights through binding identity:
/// dismiss, dispose and reopen swap the binding.
class PopupSelectController {
  PopupSelectController({required this.consume, required this.focusComposer});

  /// Consume the open-time token segment after a successful select; false (a
  /// guard miss) is benign and never retried.
  final bool Function(TokenSegment segment) consume;

  /// Return the keyboard to the composer.
  final void Function() focusComposer;

  final Observable<PopupState> state = Observable(const PopupState());
  _Binding? _binding;

  /// Open the popup for one command, fetching its options once. A reopen
  /// supersedes the previous popup.
  void open(
    String command,
    PopupSelectSpec spec,
    String sessionId,
    TokenSegment segment,
  ) {
    final labels = spec.searchLabels?.call();
    _binding?.abort.abort();
    final binding = _Binding(command, spec, sessionId, segment);
    _binding = binding;
    state.set(
      PopupState(
        open: true,
        command: command,
        searchLabels: labels,
        searchMode: spec.searchMode,
      ),
    );
    _load(binding);
  }

  void _load(_Binding binding) {
    binding.spec
        .options(binding.sessionId, binding.abort.signal)
        .then(
          (options) {
            if (_binding != binding) return;
            final cur = state.value;
            state.set(
              cur.copyWith(
                status: PopupStatus.ready,
                options: options,
                active: _currentIndex(options, cur.search, cur.searchMode),
                error: null,
              ),
            );
          },
          onError: (Object error) {
            if (_binding != binding) return;
            state.set(
              state.value.copyWith(
                status: PopupStatus.failed,
                options: const [],
                active: 0,
                error: '$error',
              ),
            );
          },
        );
  }

  /// Re-run a failed options fetch (the search survives).
  void retry() {
    final binding = _binding;
    final s = state.value;
    if (binding == null || !s.open || s.status != PopupStatus.failed) return;
    state.set(s.copyWith(status: PopupStatus.pending, error: null));
    _load(binding);
  }

  /// Replace the local search text (the provider is never re-queried) and
  /// rebase the highlight to the top: typing searches for something other than
  /// the current value.
  void setSearch(String search) {
    final s = state.value;
    if (!s.open || s.submitting || s.confirming != null || search == s.search) {
      return;
    }
    state.set(s.copyWith(search: search, active: 0));
  }

  /// Move the highlight across the filtered rows, wrapping.
  void move(int dir) {
    final s = state.value;
    if (!s.open ||
        s.status != PopupStatus.ready ||
        s.submitting ||
        s.confirming != null) {
      return;
    }
    final rows = filterOptions(s.options, s.search, s.searchMode);
    if (rows.isEmpty) return;
    state.set(s.copyWith(active: (s.active + dir + rows.length) % rows.length));
  }

  /// Set the highlight directly (pointer hover).
  void highlight(int index) {
    final s = state.value;
    if (!s.open ||
        s.status != PopupStatus.ready ||
        s.submitting ||
        s.confirming != null) {
      return;
    }
    final n = filterOptions(s.options, s.search, s.searchMode).length;
    if (index < 0 || index >= n || index == s.active) return;
    state.set(s.copyWith(active: index));
  }

  /// Select one filtered row: single-flight. Success consumes the token
  /// segment, closes and returns the keyboard to the composer. Failure keeps
  /// the popup open with its search, highlight and token, and surfaces the
  /// error.
  Future<void> select(int index) async {
    final binding = _binding;
    final s = state.value;
    if (binding == null ||
        !s.open ||
        s.status != PopupStatus.ready ||
        s.submitting ||
        s.confirming != null) {
      return;
    }
    final rows = filterOptions(s.options, s.search, s.searchMode);
    if (index < 0 || index >= rows.length) return;
    final option = rows[index];
    if (option.confirmation != null) {
      state.set(
        s.copyWith(confirming: option, acknowledged: false, error: null),
      );
      return;
    }
    await _settle(binding, option);
  }

  void acknowledge(bool acknowledged) {
    final s = state.value;
    if (!s.open ||
        s.submitting ||
        s.confirming == null ||
        s.acknowledged == acknowledged) {
      return;
    }
    state.set(s.copyWith(acknowledged: acknowledged));
  }

  /// Cancel only the risk gate; the option picker stays open.
  void cancelConfirmation() {
    final s = state.value;
    if (!s.open || s.submitting || s.confirming == null) return;
    state.set(s.copyWith(confirming: null, acknowledged: false));
  }

  /// Settle the gated option once the checkbox is acknowledged.
  Future<void> confirm() async {
    final binding = _binding;
    final s = state.value;
    if (binding == null ||
        !s.open ||
        s.submitting ||
        s.confirming == null ||
        !s.acknowledged) {
      return;
    }
    await _settle(binding, s.confirming!);
  }

  Future<void> _settle(_Binding binding, SelectOption option) async {
    final s = state.value;
    if (_binding != binding || !s.open || s.submitting) return;
    state.set(
      s.copyWith(
        submitting: true,
        confirming: null,
        acknowledged: false,
        error: null,
      ),
    );
    try {
      await binding.spec.onSelect(option, binding.sessionId);
    } on Object catch (error) {
      if (_binding != binding) return;
      state.set(state.value.copyWith(submitting: false, error: '$error'));
      return;
    }
    if (_binding != binding) return; // late success: no write, no consumption
    consume(binding.segment);
    _binding = null;
    state.set(const PopupState());
    focusComposer();
  }

  /// Close the popup; aborts a flying options fetch and revokes settlement
  /// rights. A press outside dismisses plainly; Escape also restores focus.
  void dismiss({bool focus = false}) {
    if (_binding == null) return;
    _binding!.abort.abort();
    _binding = null;
    state.set(const PopupState());
    if (focus) focusComposer();
  }

  /// The command the popup is open for, if any.
  String? get openCommand => state.value.command;

  /// Teardown: abort in-flight work and clear state (no focus side effect).
  void dispose() {
    _binding?.abort.abort();
    _binding = null;
    state.set(const PopupState());
  }
}
