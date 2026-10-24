import 'dart:async';

import 'package:dsh_conversation/dsh_conversation.dart';

/// A scriptable trigger source for the pipeline tests.
class FakeSource extends InputTriggerSource {
  FakeSource({
    required this.sourceName,
    this.char = TriggerChar.at,
    this.rows = const [],
    this.group = true,
    this.order0 = 0,
  });

  final String sourceName;
  final TriggerChar char;
  List<InputTriggerCandidate> rows;
  final bool group;
  final int order0;

  /// Requests seen, newest last.
  final List<CandidateRequest> requests = [];

  /// Completers the test resolves by hand; empty means answer at once.
  final List<(CandidateRequest, Completer0)> pending = [];
  bool hold = false;
  Object? failWith;
  final List<InputTriggerPick> picks = [];
  PickOutcome? Function(InputTriggerPick pick)? onPickFn;
  final List<String> warmed = [];

  @override
  TriggerChar get trigger => char;
  @override
  String get name => sourceName;
  @override
  int get order => order0;
  @override
  bool get showGroupTitle => group;

  @override
  Future<List<InputTriggerCandidate>> candidates(
    String sessionId,
    CandidateRequest req,
  ) {
    requests.add(req);
    if (failWith != null) return Future.error(failWith!);
    if (hold) {
      final c = Completer0();
      pending.add((req, c));
      return c.future;
    }
    return Future.value(rows);
  }

  @override
  PickOutcome? onPick(InputTriggerPick pick) {
    picks.add(pick);
    return onPickFn?.call(pick);
  }

  @override
  void warm(String sessionId) => warmed.add(sessionId);
}

typedef Completer0 = Completer<List<InputTriggerCandidate>>;

/// A reference source with the file codec of dsh's `@` source.
class FakeReferenceSource extends FakeSource {
  FakeReferenceSource() : super(sourceName: 'reference', group: false);

  final List<String> serialized = [];
  Object? serializeError;

  @override
  ReferenceCodec get codec => _Codec(this);
}

class _Codec implements ReferenceCodec {
  _Codec(this.owner);
  final FakeReferenceSource owner;
  @override
  String clipboardText(String ref) => ref;
  @override
  Future<String> serialize(String ref, AbortSignal signal) async {
    owner.serialized.add(ref);
    if (owner.serializeError != null) throw owner.serializeError!;
    return ref;
  }
}

/// Command source answering Enter, space and claims from a table.
class FakeCommandSource extends InputTriggerSource {
  FakeCommandSource({this.known = const {}});

  /// Names that take input (claims) by catalog name.
  final Set<String> known;
  final List<String> executed = [];
  Object? enterError;

  @override
  TriggerChar get trigger => TriggerChar.slash;
  @override
  String get name => 'command';
  @override
  bool get adjudicatesEnter => true;
  @override
  bool get adjudicatesSpace => true;

  @override
  Future<List<InputTriggerCandidate>> candidates(
    String sessionId,
    CandidateRequest req,
  ) async => [for (final n in known) InputTriggerCandidate(name: n)];

  @override
  PickOutcome? onPick(InputTriggerPick pick) => null;

  CommandClaim _claim(String n) => CommandClaim(
    name: n,
    token: '/$n ',
    submit: (args, attachments) async {
      executed.add('/$n $args');
      return const SubmitOutcome.success();
    },
  );

  @override
  PickOutcome? matchSpace(String sessionId, String token) {
    final n = token.startsWith('/') ? token.substring(1) : token;
    return known.contains(n) ? PickClaim(_claim(n)) : null;
  }

  @override
  Future<PickOutcome?> matchEnter(
    String sessionId,
    String line,
    AbortSignal signal,
    SubmitEnvelope envelope,
  ) async {
    if (enterError != null) throw enterError!;
    final trimmed = line.trim();
    final ws = trimmed.indexOf(RegExp(r'\s'));
    final n = (ws == -1 ? trimmed : trimmed.substring(0, ws)).substring(1);
    return known.contains(n) ? PickClaim(_claim(n)) : null;
  }
}
