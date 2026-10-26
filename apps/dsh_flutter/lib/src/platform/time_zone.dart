import 'dart:io';

import 'package:flutter/services.dart';

/// Native IANA identity, never a seasonal abbreviation such as CST or JST.
/// An unknown platform falls back explicitly to UTC; the task editor always
/// exposes the chosen zone and sends it to the Host for authoritative conversion.
Future<String> readDeviceTimeZone() async {
  if (Platform.isAndroid) {
    try {
      final zone = await const MethodChannel('app.kevinzhow.whalee/platform')
          .invokeMethod<String>('timeZone');
      if (zone != null && zone.isNotEmpty) return zone;
    } on PlatformException {
      // No fabricated IANA identity on platform failure.
    } on MissingPluginException {
      // A host without the bridge uses the explicit fallback.
    }
  }
  if (Platform.isLinux || Platform.isMacOS) {
    final environment = Platform.environment['TZ'];
    if (environment != null &&
        environment.isNotEmpty &&
        !environment.startsWith(':') &&
        !environment.startsWith('/')) {
      return environment;
    }
    try {
      final target = await File('/etc/localtime').resolveSymbolicLinks();
      final marker = '/zoneinfo/';
      final at = target.indexOf(marker);
      if (at >= 0) return target.substring(at + marker.length);
    } on FileSystemException {
      // Try the next native source.
    }
    try {
      final zone = (await File('/etc/timezone').readAsString()).trim();
      if (zone.isNotEmpty) return zone;
    } on FileSystemException {
      // Try the next native source.
    }
  }
  return 'UTC';
}
