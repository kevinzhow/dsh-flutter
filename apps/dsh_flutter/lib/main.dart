import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/backend.dart';
import 'src/debug_controller.dart';

void main() {
  runApp(DshApp(controller: DebugController(LiveBackend())));
}
