/// Pure Dart transport for DSH hosts (dsh's `client/connection` + `api/gateway`
/// client layers): pairing, connection generations, the `/api/remote.mux`
/// WebSocket, and unary `POST /api/<ns>/<method>`.
library;

export 'src/connection.dart';
export 'src/events.dart';
export 'src/host_info.dart';
export 'src/ids.dart' show randomUuid;
export 'src/mux.dart';
export 'src/pairing.dart';
export 'src/remote_caller.dart';
export 'src/unary.dart';
