import 'package:dsh_client/dsh_client.dart' show CertificateInfo;
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show Icons, SelectableText;
import 'package:flutter/widgets.dart';

import '../app_controller.dart';

/// The decision about a certificate nobody has vouched for (first contact) or
/// one that is not the trusted one any more (a change). It shows the SHA-256
/// fingerprint to compare with the host, and offers nothing that connects
/// without the user choosing it: no request, and no token, has gone out.
class CertificateCard extends StatelessWidget {
  const CertificateCard({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final prompt = controller.certificatePrompt!;
    final theme = context.dsh;
    final i18n = controller.i18n;
    String a(String key, [Map<String, Object?> params = const {}]) =>
        i18n.t(appNamespace, key, params: params);
    final warning = prompt.changed && !prompt.acknowledged;
    final host = prompt.origin.hasPort
        ? '${prompt.origin.host}:${prompt.origin.port}'
        : prompt.origin.host;
    final title = prompt.changed
        ? a('cert.changed.title')
        : a('cert.trust.title');
    final body = warning
        ? a('cert.changed.body', {'host': host})
        : a('cert.trust.body', {'host': host});
    TextStyle label() => theme
        .textStyle('--dsw-font-xs-strong-13')
        .copyWith(color: theme.labelSecondary);
    TextStyle small() => theme
        .textStyle('--dsw-font-xxs-12')
        .copyWith(color: theme.labelSecondary);
    Widget fingerprint(String title, String value, {Key? key}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: label()),
        const SizedBox(height: DshSpace.xs),
        SelectableText(
          value,
          key: key,
          style: theme
              .textStyle('--dsw-font-markdown-code-block')
              .copyWith(color: theme.labelPrimary),
        ),
      ],
    );
    final cert = prompt.certificate;
    return Container(
      key: const ValueKey('certificate-card'),
      padding: const EdgeInsets.all(DshSpace.md),
      decoration: BoxDecoration(
        color: theme.color('--dsw-alias-state-warn-tertiary'),
        borderRadius: BorderRadius.circular(theme.radiusMd),
        border: warning
            ? Border.all(color: theme.color('--dsw-alias-state-error-primary'))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                warning ? Icons.gpp_maybe_outlined : Icons.lock_outline,
                size: 18,
                color: warning
                    ? theme.color('--dsw-alias-state-error-primary')
                    : theme.color('--dsw-alias-state-warn-label'),
              ),
              const SizedBox(width: DshSpace.sm),
              Expanded(
                child: Text(
                  title,
                  key: const ValueKey('certificate-title'),
                  style: theme
                      .textStyle('--dsw-font-m-18')
                      .copyWith(color: theme.labelPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: DshSpace.sm),
          Text(
            body,
            style: theme
                .textStyle('--dsw-font-s-14')
                .copyWith(color: theme.labelPrimary),
          ),
          const SizedBox(height: DshSpace.md),
          if (prompt.changed) ...[
            fingerprint(
              a('cert.changed.before'),
              prompt.previous!,
              key: const ValueKey('certificate-previous'),
            ),
            const SizedBox(height: DshSpace.sm),
            fingerprint(
              a('cert.changed.now'),
              cert.sha256,
              key: const ValueKey('certificate-fingerprint'),
            ),
          ] else
            fingerprint(
              a('cert.fingerprint'),
              cert.sha256,
              key: const ValueKey('certificate-fingerprint'),
            ),
          if (prompt.canTrust) ...[
            const SizedBox(height: DshSpace.sm),
            Text('${a('cert.subject')}: ${_name(cert)}', style: small()),
            Text(_validity(cert, a), style: small()),
            const SizedBox(height: DshSpace.xs),
            Text(a('cert.compareHint'), style: small()),
          ],
          const SizedBox(height: DshSpace.lg),
          Wrap(
            spacing: DshSpace.sm,
            runSpacing: DshSpace.sm,
            children: [
              if (warning)
                DshButton(
                  key: const ValueKey('certificate-review'),
                  variant: DshButtonVariant.outline,
                  onPressed: controller.reviewCertificateChange,
                  child: Text(a('cert.changed.review')),
                )
              else
                DshButton(
                  key: const ValueKey('certificate-trust'),
                  variant: DshButtonVariant.primary,
                  onPressed: controller.trustCertificate,
                  child: Text(a('cert.trust.action')),
                ),
              DshButton(
                key: const ValueKey('certificate-cancel'),
                variant: warning
                    ? DshButtonVariant.primary
                    : DshButtonVariant.outline,
                onPressed: controller.declineCertificate,
                child: Text(a('cert.cancel')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _name(CertificateInfo c) => c.subject.replaceFirst('/', '');

  static String _validity(
    CertificateInfo c,
    String Function(String, [Map<String, Object?>]) a,
  ) {
    final now = DateTime.now();
    String date(DateTime d) {
      final u = d.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${u.year}-${two(u.month)}-${two(u.day)}';
    }

    if (c.expiredAt(now)) return a('cert.expired', {'date': date(c.notAfter)});
    if (c.notYetValidAt(now)) {
      return a('cert.notYetValid', {'date': date(c.notBefore)});
    }
    return a('cert.validUntil', {'date': date(c.notAfter)});
  }
}
