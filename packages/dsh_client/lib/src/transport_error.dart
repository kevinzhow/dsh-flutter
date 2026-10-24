import 'dart:async';
import 'dart:io';

import 'remote_caller.dart';

/// A short, safe description of a transport failure for the screen or a log.
///
/// It never contains a request URL (the pairing URL carries the launch token)
/// and never prints an exception object it does not know.
String describeTransportError(Object? error) => switch (error) {
  null => '',
  SocketException(:final message, :final osError) =>
    osError == null ? message : '$message (${osError.message})',
  TlsException(:final message) => message,
  HttpException(:final message) => message,
  TimeoutException() => 'timed out',
  RemoteException(:final message) => message,
  _ => error.runtimeType.toString(),
};
