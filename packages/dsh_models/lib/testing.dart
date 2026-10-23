/// Test support shared by packages that replay recorded traces through the
/// Session model: a scriptable fake transport and the behaviour-vector replayer.
/// Not part of the runtime API; import only from tests and tools.
library;

export 'src/testing/fake_transport.dart';
export 'src/testing/replay.dart';
