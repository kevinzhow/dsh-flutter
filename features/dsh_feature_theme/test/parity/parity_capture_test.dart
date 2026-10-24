// Entry point of the Flutter provider. Driven by tool/parity (PARITY_PLAN); a plain `flutter test`
// skips it.
import 'package:dsh_parity/dsh_parity.dart';

import 'case_map.dart';

void main() => runParityCapture(cases: parityCases, uncovered: parityUncovered);
