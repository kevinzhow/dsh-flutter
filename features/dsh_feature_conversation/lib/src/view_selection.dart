import 'package:dsh_models/dsh_models.dart';
import 'package:flutter/foundation.dart';

final Expando<ValueNotifier<String?>> _selections = Expando();

/// Which `conversation.view` tab of [session] is showing (dsh's per-Session
/// `view` of the conversation store); null selects the first view. The header's
/// tabs write it and the shell reads it.
ValueNotifier<String?> viewSelectionOf(Session session) =>
    _selections[session] ??= ValueNotifier<String?>(null);
