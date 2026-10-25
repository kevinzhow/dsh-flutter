/// Pure Dart transport for DSH hosts (dsh's `client/connection` + `api/gateway`
/// client layers): pairing, connection generations, the `/api/remote.mux`
/// WebSocket, and unary `POST /api/<ns>/<method>`.
library;

export 'src/binary_response.dart' show decodeBinaryResponse, multipartBoundary;
export 'src/connection.dart';
export 'src/events.dart';
export 'src/deliverables.dart';
export 'src/file_upload.dart';
export 'src/host_info.dart';
export 'src/host_scope.dart';
export 'src/ids.dart' show randomUuid;
export 'src/mux.dart';
export 'src/open_in_app.dart';
export 'src/pairing.dart';
export 'src/remote_caller.dart';
export 'src/transport_error.dart';
export 'src/trust.dart';
export 'src/unary.dart';
export 'src/workspace_files.dart';
