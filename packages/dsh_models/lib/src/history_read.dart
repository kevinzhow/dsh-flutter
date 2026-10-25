import 'dart:async';

import 'package:dsh_client/dsh_client.dart';

import 'transport.dart';

/// One bounded resource read: capture a follow snapshot, then page backwards
/// against its fixed cursor. Closing cancels the live follow and prevents any
/// further pages. This never mutates the conversation's visible history window.
class SessionHistoryRead {
  SessionHistoryRead(this._transport, this.address);
  final SessionTransport _transport;
  final Map<String, Object?> address;
  StreamIterator<GenerationFrame>? _iterator;
  bool _closed = false;

  Future<Map<String, Object?>> snapshot() async {
    if (_closed) throw StateError('history read closed');
    final iterator = _iterator = StreamIterator(
      _transport.follow(() => {'address': address}),
    );
    int? generation;
    try {
      while (!_closed && await iterator.moveNext()) {
        switch (iterator.current) {
          case StreamOpened(generation: final openedGeneration):
            // The next item is authoritative only for the current generation.
            generation = openedGeneration;
          case StreamEnded(:final error):
            throw error ??
                StateError('Session history ended before its opening snapshot');
          case StreamItem(:final value, generation: final itemGeneration):
            if (itemGeneration != generation) continue;
            if (value is Map<String, Object?> && value['type'] == 'snapshot') {
              return value;
            }
        }
      }
      throw StateError('Session history ended before its opening snapshot');
    } finally {
      await iterator.cancel();
      if (identical(_iterator, iterator)) _iterator = null;
    }
  }

  Future<Map<String, Object?>> page({
    required num throughSeq,
    required num beforeSeq,
  }) async {
    if (_closed) throw StateError('history read closed');
    final result = await _transport.page({
      'address': address,
      'throughSeq': throughSeq,
      'beforeSeq': beforeSeq,
    });
    if (_closed) throw StateError('history read closed');
    return result;
  }

  Future<void> close() async {
    _closed = true;
    await _iterator?.cancel();
  }
}
