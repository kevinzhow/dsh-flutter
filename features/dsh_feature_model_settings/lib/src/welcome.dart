import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

const welcomeNoticeVersion = '2026-09-28.1';

/// Native acknowledgement of the same versioned product notice as the Web.
/// No browser cookie, desktop identity or account credential is fabricated.
class WelcomeNotice extends StatefulWidget {
  const WelcomeNotice({
    super.key,
    required this.form,
    required this.owner,
    required this.i18n,
  });
  final ConfigForm form;
  final SettingsOnboardingOwner owner;
  final DshI18n i18n;
  @override
  State<WelcomeNotice> createState() => _WelcomeNoticeState();
}

class _WelcomeNoticeState extends State<WelcomeNotice> {
  late final void Function() off;
  bool busy = false;
  bool failed = false;
  bool _completed = false;
  String t(String key) => widget.i18n.t('settings.models', key);
  bool get acknowledged =>
      widget.form.snapshot.value?['welcomeNoticeVersion'] ==
      welcomeNoticeVersion;
  @override
  void initState() {
    super.initState();
    off = widget.form.subscribe(_derive);
    _derive();
  }

  void _derive() {
    if (acknowledged && !_completed) {
      _completed = true;
      widget.owner.complete();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    off();
    super.dispose();
  }

  Future<void> _save() async {
    if (busy) return;
    setState(() {
      busy = true;
      failed = false;
    });
    try {
      await widget.form.set('welcomeNoticeVersion', welcomeNoticeVersion);
    } on Object {
      /* remain on notice with retry */
    }
    if (!mounted) return;
    setState(() {
      busy = false;
      failed = !acknowledged;
    });
    _derive();
  }

  @override
  Widget build(BuildContext context) {
    final form = widget.form.snapshot;
    if (acknowledged || form.status == ConfigFormStatus.loading) {
      return const SizedBox.shrink();
    }
    final theme = context.dsh;
    return Stack(
      children: [
        ModalBarrier(
          dismissible: false,
          color: theme.color('--dsw-alias-bg-mask-1'),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: DshDialogFrame(
              width: 640,
              child: Semantics(
                scopesRoute: true,
                explicitChildNodes: true,
                namesRoute: true,
                label: t('welcomeTitle'),
                child: DefaultTextStyle(
                  style: theme
                      .textStyle('--dsw-font-s-14')
                      .copyWith(color: theme.labelPrimary),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          t('welcomeTitle'),
                          style: theme
                              .textStyle('--dsw-font-base-16')
                              .copyWith(color: theme.labelPrimary),
                        ),
                        const SizedBox(height: 16),
                        Text(t('welcomeBody')),
                        if (failed ||
                            form.status == ConfigFormStatus.unavailable)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              t('welcomeError'),
                              style: theme
                                  .textStyle('--dsw-font-xxs-12')
                                  .copyWith(
                                    color: theme.color(
                                      '--dsw-alias-state-error-primary',
                                    ),
                                  ),
                            ),
                          ),
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerRight,
                          child: DshButton(
                            key: const ValueKey('welcome-continue'),
                            variant: DshButtonVariant.primary,
                            onPressed: busy || !form.writable
                                ? null
                                : () => unawaited(_save()),
                            child: Text(t('welcomeContinue')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
