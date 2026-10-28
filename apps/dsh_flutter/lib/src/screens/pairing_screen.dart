import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_controller.dart';
import '../app_identity.dart';
import 'certificate_card.dart';

/// The pairing screen: the product name, then [PairingForm].
class PairingScreen extends StatelessWidget {
  const PairingScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(DshSpace.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  appDisplayName,
                  key: const ValueKey('app-name'),
                  style: theme
                      .textStyle('--dsw-font-xl-24')
                      .copyWith(color: theme.labelPrimary),
                ),
                const SizedBox(height: DshSpace.xs),
                Text(
                  controller.i18n.t(appNamespace, 'pairing.disclaimer'),
                  style: theme
                      .textStyle('--dsw-font-xxs-12')
                      .copyWith(
                        color: theme.color('--dsw-alias-label-tertiary'),
                      ),
                ),
                const SizedBox(height: DshSpace.xl),
                PairingForm(controller: controller),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The page that pairs again while the sessions stay behind it (the host
/// restarted, or its certificate changed): the same form, a way back, and it
/// closes itself once the connection is up.
class RepairRoute extends StatelessWidget {
  const RepairRoute({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.phase == ConnectionPhase.connected &&
            controller.certificatePrompt == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
              Navigator.of(context).maybePop();
            }
          });
        }
        return Scaffold(
          backgroundColor: theme.bgBase,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(DshSpace.xs),
                  child: Row(
                    children: [
                      DshButton(
                        key: const ValueKey('repair-back'),
                        profile: DshButtonProfile.iconAction,
                        semanticLabel: controller.i18n.t('common', 'back'),
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const DshIcon(
                          CharcoalIcons.arrowLeft,
                          size: DshButtonRecipe.iconSize,
                        ),
                      ),
                      Text(
                        controller.i18n.t(
                          appNamespace,
                          'connection.repair.title',
                        ),
                        style: theme
                            .textStyle('--dsw-font-m-18')
                            .copyWith(color: theme.labelPrimary),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(DshSpace.lg),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: PairingForm(controller: controller),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A launch link (typed, pasted or scanned) or a host address plus token, the
/// connect action, and the reason when pairing failed or the certificate that
/// waits for a decision.
class PairingForm extends StatefulWidget {
  const PairingForm({super.key, required this.controller});

  final AppController controller;

  @override
  State<PairingForm> createState() => _PairingFormState();
}

class _PairingFormState extends State<PairingForm> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _token = TextEditingController();
  bool _scanHint = false;
  bool _pasteEmpty = false;

  AppController get c => widget.controller;
  String _a(String key, {Map<String, Object?> params = const {}}) =>
      c.i18n.t(appNamespace, key, params: params);

  @override
  void initState() {
    super.initState();
    _url.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    setState(() {
      _pasteEmpty = text.isEmpty;
      _scanHint = false;
    });
    if (text.isEmpty) return;
    _url.text = text;
    final hasToken =
        Uri.tryParse(text)?.queryParameters['token']?.isNotEmpty ?? false;
    if (hasToken) await _connect();
  }

  Future<void> _scan() async {
    if (!c.scanner.available) {
      setState(() {
        _scanHint = true;
        _pasteEmpty = false;
      });
      return;
    }
    final text = await c.scanner.scan();
    if (text == null || !mounted) return;
    _url.text = text;
    await _connect();
  }

  Future<void> _connect() async {
    setState(() {
      _scanHint = false;
      _pasteEmpty = false;
    });
    await c.pair(_url.text, token: _token.text);
  }

  /// The typed address is plain http (an address without a scheme is read as
  /// http too): say so before anything is sent.
  bool get _plainHttp {
    final t = _url.text.trim().toLowerCase();
    return t.isNotEmpty && !t.startsWith('https://');
  }

  String? _errorText() {
    final e = c.pairingError;
    if (e == null) {
      return c.phase == ConnectionPhase.needsPairing
          ? _a('pairing.status.needsPairing')
          : null;
    }
    return switch (e.kind) {
      PairingErrorKind.invalid => _a('pairing.error.invalid'),
      PairingErrorKind.rejected => _a('pairing.error.rejected'),
      PairingErrorKind.unreachable => _a('pairing.error.unreachable'),
      PairingErrorKind.insecure => _a(
        'pairing.error.insecure',
        params: {'host': e.detail ?? ''},
      ),
      PairingErrorKind.certificate => _a('pairing.error.certificate'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    if (c.certificatePrompt != null) {
      return CertificateCard(controller: c);
    }
    final connecting = c.phase == ConnectionPhase.connecting;
    final error = _errorText();
    final saved = c.savedHostOrigin;
    TextStyle label() => theme
        .textStyle('--dsw-font-xs-strong-13')
        .copyWith(color: theme.labelSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (saved != null) ...[
          DshContainer(
            key: const ValueKey('saved-host'),
            padding: const EdgeInsets.all(DshSpace.md),
            decoration: BoxDecoration(
              color: theme.color('--dsw-alias-state-warn-tertiary'),
              borderRadius: BorderRadius.circular(theme.radiusMd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _a('pairing.saved.unreachable', params: {'host': saved}),
                  style: theme
                      .textStyle('--dsw-font-s-14')
                      .copyWith(color: theme.labelPrimary),
                ),
                const SizedBox(height: DshSpace.xs),
                Text(
                  _a('connection.unreachable.body', params: {'host': saved}),
                  style: theme
                      .textStyle('--dsw-font-xxs-12')
                      .copyWith(color: theme.labelSecondary),
                ),
                const SizedBox(height: DshSpace.md),
                Wrap(
                  spacing: DshSpace.sm,
                  runSpacing: DshSpace.sm,
                  children: [
                    DshButton(
                      key: const ValueKey('saved-host-retry'),
                      variant: DshButtonVariant.primary,
                      onPressed: connecting ? null : c.retrySavedHost,
                      child: Text(_a('pairing.saved.tryAgain')),
                    ),
                    DshButton(
                      key: const ValueKey('saved-host-forget'),
                      variant: DshButtonVariant.outline,
                      onPressed: c.forgetSavedHost,
                      child: Text(_a('pairing.saved.forget')),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: DshSpace.lg),
        ],
        Text(
          _a('pairing.title'),
          style: theme
              .textStyle('--dsw-font-m-18')
              .copyWith(color: theme.labelPrimary),
        ),
        const SizedBox(height: DshSpace.sm),
        Text(
          _a('pairing.intro'),
          style: theme
              .textStyle('--dsw-font-s-14')
              .copyWith(color: theme.labelSecondary),
        ),
        const SizedBox(height: DshSpace.lg),
        Text(_a('pairing.field.url'), style: label()),
        const SizedBox(height: DshSpace.xs),
        DshTextField(
          key: const ValueKey('pairing-url'),
          controller: _url,
          placeholder: _a('pairing.field.url.placeholder'),
          keyboardType: TextInputType.url,
          enabled: !connecting,
          autofocus: saved == null,
          textInputAction: TextInputAction.next,
        ),
        if (_plainHttp)
          Padding(
            padding: const EdgeInsets.only(top: DshSpace.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DshIcon(
                  CharcoalIcons.warning,
                  size: 14,
                  color: theme.color('--dsw-alias-state-warn-label'),
                ),
                const SizedBox(width: DshSpace.xs),
                Expanded(
                  child: Text(
                    _a('pairing.http.notice'),
                    key: const ValueKey('pairing-http-notice'),
                    style: theme
                        .textStyle('--dsw-font-xxs-12')
                        .copyWith(
                          color: theme.color('--dsw-alias-state-warn-label'),
                        ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: DshSpace.md),
        Text(_a('pairing.field.token'), style: label()),
        const SizedBox(height: DshSpace.xs),
        DshTextField(
          key: const ValueKey('pairing-token'),
          controller: _token,
          obscure: true,
          enabled: !connecting,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _connect(),
        ),
        const SizedBox(height: DshSpace.md),
        Wrap(
          spacing: DshSpace.sm,
          runSpacing: DshSpace.sm,
          children: [
            DshButton(
              key: const ValueKey('pairing-paste'),
              variant: DshButtonVariant.outline,
              icon: DshIcon(CharcoalIcons.paste, size: 16),
              onPressed: connecting ? null : _paste,
              child: Text(_a('pairing.action.paste')),
            ),
            DshButton(
              key: const ValueKey('pairing-scan'),
              variant: DshButtonVariant.outline,
              icon: DshIcon(CharcoalIcons.scan, size: 16),
              onPressed: connecting ? null : _scan,
              child: Text(_a('pairing.action.scan')),
            ),
          ],
        ),
        if (_scanHint || _pasteEmpty)
          Padding(
            padding: const EdgeInsets.only(top: DshSpace.sm),
            child: Text(
              _scanHint
                  ? _a('pairing.scan.unavailable')
                  : _a('pairing.paste.empty'),
              key: const ValueKey('pairing-hint'),
              style: theme
                  .textStyle('--dsw-font-xxs-12')
                  .copyWith(color: theme.labelSecondary),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: DshSpace.md),
            child: Text(
              error,
              key: const ValueKey('pairing-error'),
              style: theme
                  .textStyle('--dsw-font-s-14')
                  .copyWith(
                    color: theme.color('--dsw-alias-state-error-primary'),
                  ),
            ),
          ),
        const SizedBox(height: DshSpace.lg),
        DshButton(
          key: const ValueKey('pairing-connect'),
          variant: DshButtonVariant.primary,
          onPressed: connecting ? null : _connect,
          child: Text(
            connecting
                ? _a('pairing.status.connecting')
                : _a('pairing.action.connect'),
          ),
        ),
      ],
    );
  }
}
