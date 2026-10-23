/// Approval feature (dsh `ui-approval`): pending-approval tracking from
/// forwarded host events, the composer takeover panel, and its slot
/// registration. Talks to the rest of the app only through slots, the injected
/// event stream and answer callback.
library;

export 'src/approval_panel.dart';
export 'src/approval_tracker.dart';
export 'src/register.dart';
