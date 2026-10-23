/// Widget test support: an app shell with the official theme resolved into the
/// ambient `Theme`. Import only from tests.
library;

import 'dsh_theme.dart';

import 'package:flutter/material.dart';

/// A [MaterialApp] whose theme carries the official dsh contract.
Widget dshTestApp(
  Widget child, {
  Brightness brightness = Brightness.light,
  Size? size,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(
    brightness: brightness,
    extensions: [resolveTheme(officialPack, ThemeSettings(), brightness)],
  ),
  home: Scaffold(
    body: size == null
        ? child
        : MediaQuery(
            data: MediaQueryData(size: size),
            child: child,
          ),
  ),
);
