import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_controller.dart';
import '../app_identity.dart';

/// The pairing screen: a launch link (typed, pasted or scanned) or a host
/// address plus token, the connect action, and the reason when pairing failed.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _token = TextEditingController();
  bool _scanHint = false;
  bool _pasteEmpty = false;

  AppController get c => widget.controller;
  String _a(String key, {Map<String, Object?> params = const {}}) =>
      c.i18n.t(appNamespace, key, params: params);

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
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final connecting = c.phase == ConnectionPhase.connecting;
    final error = _errorText();
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
                  _a('pairing.disclaimer'),
                  style: theme
                      .textStyle('--dsw-font-xxs-12')
                      .copyWith(
                        color: theme.color('--dsw-alias-label-tertiary'),
                      ),
                ),
                const SizedBox(height: DshSpace.xl),
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
                Text(
                  _a('pairing.field.url'),
                  style: theme
                      .textStyle('--dsw-font-xs-strong-13')
                      .copyWith(color: theme.labelSecondary),
                ),
                const SizedBox(height: DshSpace.xs),
                DshTextField(
                  key: const ValueKey('pairing-url'),
                  controller: _url,
                  placeholder: _a('pairing.field.url.placeholder'),
                  keyboardType: TextInputType.url,
                  enabled: !connecting,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: DshSpace.md),
                Text(
                  _a('pairing.field.token'),
                  style: theme
                      .textStyle('--dsw-font-xs-strong-13')
                      .copyWith(color: theme.labelSecondary),
                ),
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
                      icon: const Icon(Icons.content_paste),
                      onPressed: connecting ? null : _paste,
                      child: Text(_a('pairing.action.paste')),
                    ),
                    DshButton(
                      key: const ValueKey('pairing-scan'),
                      variant: DshButtonVariant.outline,
                      icon: const Icon(Icons.qr_code_scanner),
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
                            color: theme.color(
                              '--dsw-alias-state-error-primary',
                            ),
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
            ),
          ),
        ),
      ),
    );
  }
}
