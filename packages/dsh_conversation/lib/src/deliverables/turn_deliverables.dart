import 'dart:convert';

import '../contract.dart';
import '../event.dart';
import '../chat/projection.dart' show asRecord;

class ProducedPath {
  const ProducedPath({
    required this.seq,
    required this.path,
    this.argumentPath,
  });
  final num seq;
  final String path;
  final String? argumentPath;
}

class PresentedPath {
  const PresentedPath({
    required this.seq,
    required this.index,
    required this.path,
    this.description,
  });
  final num seq;
  final int index;
  final String path;
  final String? description;
}

class ChangesTurnData {
  const ChangesTurnData(this.seq);
  final num seq;
}

class DeliverablesTurnData {
  const DeliverablesTurnData({
    this.produced = const [],
    this.presented = const [],
    this.changes,
  });
  final List<ProducedPath> produced;
  final List<PresentedPath> presented;
  final ChangesTurnData? changes;
}

class _DeliverablesState extends DeliverablesTurnData {
  const _DeliverablesState({
    required this.turn,
    this.calls = const {},
    super.produced,
    super.presented,
    super.changes,
  });
  final int turn;
  final Map<String, String?> calls;
  _DeliverablesState copy({
    Map<String, String?>? calls,
    List<ProducedPath>? produced,
    List<PresentedPath>? presented,
    ChangesTurnData? changes,
  }) => _DeliverablesState(
    turn: turn,
    calls: calls ?? this.calls,
    produced: produced ?? this.produced,
    presented: presented ?? this.presented,
    changes: changes ?? this.changes,
  );
}

String? _path(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;
bool _absolute(String value) =>
    value.startsWith('/') ||
    value.startsWith(r'\\') ||
    RegExp(r'^[A-Za-z]:[/\\]').hasMatch(value);
bool _integer(Object? value) =>
    value is num && value.isFinite && value.truncateToDouble() == value;
bool _safeInteger(Object? value) =>
    _integer(value) && (value as num).abs() <= 9007199254740991;

/// Only complete supported mutation calls are evidence of a produced path.
String? mutationPath(String name, String argsRaw) {
  Object? value;
  try {
    value = jsonDecode(argsRaw);
  } on FormatException {
    return null;
  }
  final args = asRecord(value);
  if (args == null) return null;
  switch (name) {
    case 'write':
      return args['content'] is String ? _path(args['file_path']) : null;
    case 'edit':
      return args['old_string'] is String &&
              (args['old_string'] as String).isNotEmpty &&
              args['new_string'] is String &&
              args['old_string'] != args['new_string'] &&
              (!args.containsKey('replace_all') || args['replace_all'] is bool)
          ? _path(args['file_path'])
          : null;
    case 'str_replace_editor':
      final path = _path(args['path']);
      if (path == null) return null;
      return switch (args['command']) {
        'create' => args['file_text'] is String ? path : null,
        'str_replace' =>
          args['old_str'] is String &&
                  (args['old_str'] as String).isNotEmpty &&
                  (!args.containsKey('new_str') || args['new_str'] is String)
              ? path
              : null,
        'insert' =>
          _integer(args['insert_line']) &&
                  (args['insert_line'] as num) >= 0 &&
                  args['new_str'] is String
              ? path
              : null,
        _ => null,
      };
    default:
      return null;
  }
}

String? mutationResultPath(String argumentPath, Object? meta) {
  final record = asRecord(meta);
  if (record == null || !record.containsKey('path')) return argumentPath;
  final recorded = record['path'];
  if (recorded is String && _absolute(recorded)) return recorded;
  return _absolute(argumentPath) ? argumentPath : null;
}

bool isPresentedFile(Object? value) {
  final file = asRecord(value);
  return file != null &&
      _path(file['path']) != null &&
      (!file.containsKey('description') || file['description'] is String);
}

bool isPresentedData(Object? value) {
  final data = asRecord(value);
  return data != null &&
      _safeInteger(data['turn']) &&
      (data['turn'] as num) >= 1 &&
      data['callId'] is String &&
      (data['callId'] as String).isNotEmpty &&
      data['files'] is List;
}

bool isChangesEvent(Object? value) {
  final data = asRecord(value);
  return data != null &&
      _safeInteger(data['turn']) &&
      (data['turn'] as num) >= 1;
}

List<String> producedForClosing(
  DeliverablesTurnData? data, [
  num seq = double.infinity,
]) {
  final seen = <String>{};
  return [
    for (final produced in data?.produced ?? const <ProducedPath>[])
      if (produced.seq <= seq && seen.add(produced.path)) produced.path,
  ];
}

List<PresentedPath> presentedForClosing(DeliverablesTurnData? data, num seq) {
  final paths = <String, PresentedPath>{};
  for (final file in data?.presented ?? const <PresentedPath>[]) {
    if (file.seq < seq) paths[file.path] = file;
  }
  return paths.values.toList();
}

String workspaceBasename(String path) => path.substring(
  (path.lastIndexOf('/') > path.lastIndexOf(r'\')
          ? path.lastIndexOf('/')
          : path.lastIndexOf(r'\')) +
      1,
);

/// Resolve only exact, unique-basename or recorded argument aliases. Unknown
/// or ambiguous closing-prose tokens stay inert.
String? resolveProducedFileMention(
  List<String> paths,
  String value, {
  List<ProducedPath> operations = const [],
}) {
  final matches = {
    for (final path in paths)
      if (path == value || workspaceBasename(path) == value) path,
  };
  for (final operation in operations) {
    if (operation.argumentPath == value) matches.add(operation.path);
  }
  return matches.length == 1 ? matches.single : null;
}

class DeliverablesDefinition extends ConversationDefinition {
  const DeliverablesDefinition();
  @override
  String get kind => 'deliverables';
  @override
  Set<String> get eventTypes => const {
    'turn/start',
    'tool/call',
    'tool/result',
    'deliverables/presented',
    'workspace/changes',
  };
  @override
  MatchResult? match(ConvEvent event) {
    final type = event.type;
    if (type == 'turn/start') {
      return MatchResult('${event.data['turn']}', MatchRole.start);
    }
    if (type == 'tool/call' ||
        type == 'deliverables/presented' && isPresentedData(event.data) ||
        type == 'workspace/changes' && isChangesEvent(event.data) ||
        type == 'tool/result' && event.isAppendSurface) {
      return MatchResult('${event.data['turn']}', MatchRole.update);
    }
    return null;
  }

  @override
  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  ) {
    if (match.event.type != 'turn/start') {
      throw StateError('Deliverables require turn/start');
    }
    return _DeliverablesState(turn: (match.event.data['turn'] as num).toInt());
  }

  @override
  Object update(NodeContext context, ConversationMatch match) {
    final state = context.state as _DeliverablesState, event = match.event;
    if (event.type == 'workspace/changes') {
      return state.copy(changes: ChangesTurnData(event.seq));
    }
    if (event.type == 'deliverables/presented') {
      final files = event.data['files'] as List;
      final presented = <PresentedPath>[];
      for (var index = 0; index < files.length; index++) {
        if (!isPresentedFile(files[index])) continue;
        final file = asRecord(files[index])!;
        presented.add(
          PresentedPath(
            seq: event.seq,
            index: index,
            path: file['path'] as String,
            description: file['description'] as String?,
          ),
        );
      }
      return presented.isEmpty
          ? state
          : state.copy(
              presented: List.unmodifiable([...state.presented, ...presented]),
            );
    }
    if (event.type == 'tool/call') {
      return state.copy(
        calls: {
          ...state.calls,
          '${event.data['callId']}': mutationPath(
            '${event.data['name']}',
            '${event.data['arguments']}',
          ),
        },
      );
    }
    if (event.type != 'tool/result') return state;
    final message = asRecord(event.data['message']);
    if (message == null || message['isError'] == true) return state;
    final id = '${asRecord(message['source'])?['callId']}';
    final argumentPath = state.calls[id];
    if (argumentPath == null) return state;
    final path = mutationResultPath(argumentPath, event.data['meta']);
    return path == null
        ? state
        : state.copy(
            produced: List.unmodifiable([
              ...state.produced,
              ProducedPath(
                seq: event.seq,
                path: path,
                argumentPath: path == argumentPath ? null : argumentPath,
              ),
            ]),
          );
  }

  @override
  LocationData? buildLocationData(
    NodeContext context,
    LocationScope scope,
    LocationData? previous,
  ) {
    final state = context.state;
    if (scope != LocationScope.turn || state is! _DeliverablesState) {
      return null;
    }
    final old = previous?.value;
    if (previous?.scope == LocationScope.turn &&
        previous?.turn == state.turn &&
        previous?.key == kind &&
        old is DeliverablesTurnData &&
        identical(old.produced, state.produced) &&
        identical(old.presented, state.presented) &&
        identical(old.changes, state.changes)) {
      return previous;
    }
    return LocationData.turn(
      turn: state.turn,
      key: kind,
      value: DeliverablesTurnData(
        produced: state.produced,
        presented: state.presented,
        changes: state.changes,
      ),
    );
  }
}
