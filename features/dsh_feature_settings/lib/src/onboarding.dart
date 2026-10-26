import 'dart:async';

import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

class SettingsOnboarding extends StatefulWidget {
  const SettingsOnboarding({
    super.key,
    required this.slots,
    required this.openSection,
  });
  final SlotRegistry slots;
  final ValueChanged<String> openSection;
  @override
  State<SettingsOnboarding> createState() => _SettingsOnboardingState();
}

class _SettingsOnboardingState extends State<SettingsOnboarding> {
  final _completed = <String>{};
  StreamSubscription<String>? _sub;
  final seat = DshSlots.settingsOnboarding
      .typed<SettingsOnboardingOwner, Widget>();
  @override
  void initState() {
    super.initState();
    _sub = widget.slots.changes.listen((name) {
      if (name == seat.name && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.slots
        .entries(seat)
        .where((e) => !_completed.contains(e.id));
    if (entries.isEmpty) return const SizedBox.shrink();
    final id = entries.first.id;
    return widget.slots.renderOnly(
          seat,
          id,
          SettingsOnboardingOwner(
            stepId: id,
            explicit: false,
            complete: () {
              scheduleMicrotask(() {
                if (mounted) setState(() => _completed.add(id));
              });
            },
            openSection: widget.openSection,
          ),
        ) ??
        const SizedBox.shrink();
  }
}
