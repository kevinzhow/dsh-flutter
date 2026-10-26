import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'common.dart';

Future<void> showPluginInstall(
  BuildContext context,
  PluginManagerModel model,
  DshI18n i18n,
) async {
  // Closing a pending dialog asks the Host to cancel and retains its identity.
  model.installer.open = true;
  await showDshDialog<void>(
    context,
    width: 600,
    label: i18n.t('pluginManager', 'installTitle'),
    builder: (_) => _InstallDialog(model: model, i18n: i18n),
  );
  await model.installer.close();
}

class _InstallDialog extends StatefulWidget {
  const _InstallDialog({required this.model, required this.i18n});
  final PluginManagerModel model;
  final DshI18n i18n;
  @override
  State<_InstallDialog> createState() => _InstallDialogState();
}

class _InstallDialogState extends State<_InstallDialog> {
  PluginInstaller get install => widget.model.installer;
  StreamSubscription<int>? _sub;
  bool guide = false, registries = false;
  String t(String key, [Map<String, Object?> p = const {}]) =>
      widget.i18n.t('pluginManager', key, params: p);
  @override
  void initState() {
    super.initState();
    _sub = install.changed.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  Future<void> _approve() async {
    widget.model.requestBuildApproval();
    final confirmation = widget.model.confirmation;
    if (confirmation == null) return;
    final accepted = await showDshDialog<bool>(
      context,
      width: 460,
      label: t('installApprovalTitle'),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            pluginHeading(context, t('installApprovalTitle')),
            const SizedBox(height: 12),
            pluginStatus(context, t('installApprovalDescription')),
            const SizedBox(height: 8),
            for (final package in confirmation.pendingBuilds) Text(package),
            const SizedBox(height: 12),
            pluginStatus(context, t('installApprovalConsequence')),
            pluginStatus(context, t('installApprovalCaution')),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                DshButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(t('cancel')),
                ),
                DshButton(
                  variant: DshButtonVariant.primary,
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(t('installApproveAndRetry')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      await widget.model.confirm(confirmation);
    } else {
      widget.model.cancelConfirmation();
    }
  }

  String get _phaseTitle => t(switch (install.phase) {
    PluginInstallPhase.idle => 'installTitle',
    PluginInstallPhase.checking => 'installChecking',
    PluginInstallPhase.starting => 'installStarting',
    PluginInstallPhase.running => 'installingTitle',
    PluginInstallPhase.cancelling => 'installCancelling',
    PluginInstallPhase.applying => 'installApplying',
    PluginInstallPhase.unconfirmed => 'installUnconfirmedTitle',
    PluginInstallPhase.unknown => 'installUnknownTitle',
    PluginInstallPhase.done => 'installedTitle',
    PluginInstallPhase.failed => 'installFailedTitle',
  });
  @override
  Widget build(BuildContext context) {
    final editing =
        install.phase == PluginInstallPhase.idle ||
        install.phase == PluginInstallPhase.checking;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: pluginHeading(context, _phaseTitle)),
              DshButton(
                size: DshButtonSize.sm,
                onPressed: () => Navigator.of(context).pop(),
                child: Text(t('close')),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (editing) ...[
            pluginStatus(context, t('installDescription')),
            const SizedBox(height: 16),
            PluginInput(
              key: const ValueKey('plugin-install-spec'),
              value: install.spec,
              label: t('installSpecLabel'),
              enabled: install.phase == PluginInstallPhase.idle,
              onChanged: install.edit,
            ),
            if (install.inputError case final refused?)
              pluginStatus(
                context,
                t(
                  switch (refused.problem.value) {
                    'invalid-spec' => 'installProblemInvalid',
                    'already-installed' =>
                      install.error == 'shipped'
                          ? 'installProblemShipped'
                          : 'installProblemInstalled',
                    'not-found' => 'installProblemNotFound',
                    'not-a-package' => 'installProblemNotPackage',
                    'not-a-bundle' => 'installProblemNotBundle',
                    'network' => 'installProblemNetwork',
                    _ => 'installProblemUnknown',
                  },
                  {'reason': refused.reason},
                ),
              ),
            if (install.error != null && install.inputError == null)
              pluginStatus(
                context,
                install.error == 'template-git'
                    ? t('installGitTemplateHint')
                    : install.error == 'template-path'
                    ? t('installPathTemplateHint')
                    : install.error!,
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: DshButton(
                size: DshButtonSize.sm,
                onPressed: () => setState(() => guide = !guide),
                child: Text(t('installGuideToggle')),
              ),
            ),
            if (guide) ...[
              pluginStatus(context, t('installGuideIdHint')),
              const SizedBox(height: 8),
              pluginStatus(context, t('installGuideSafety')),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: DshButton(
                size: DshButtonSize.sm,
                onPressed: () => setState(() => registries = !registries),
                child: Text(t('registryToggle')),
              ),
            ),
            if (registries) ...[
              for (final registry in pluginRegistryOffers(install.registries))
                Align(
                  alignment: Alignment.centerLeft,
                  child: DshButton(
                    size: DshButtonSize.sm,
                    variant:
                        !install.registry.custom &&
                            install.registry.registry == registry
                        ? DshButtonVariant.toolbar
                        : DshButtonVariant.ghost,
                    onPressed: () => install.chooseRegistry(
                      PluginRegistryChoice.offered(registry),
                    ),
                    child: Text(
                      registry == null
                          ? t('registryDefault')
                          : Uri.tryParse(registry)?.host ?? registry,
                    ),
                  ),
                ),
              DshButton(
                size: DshButtonSize.sm,
                onPressed: () => install.chooseRegistry(
                  const PluginRegistryChoice.custom(''),
                ),
                child: Text(t('registryCustom')),
              ),
              if (install.registry.custom)
                PluginInput(
                  value: install.registry.registry ?? '',
                  label: t('registryCustom'),
                  onChanged: (value) => install.chooseRegistry(
                    PluginRegistryChoice.custom(value),
                  ),
                ),
              if (install.registryError)
                pluginStatus(context, t('registryCustomInvalid')),
            ],
          ] else ...[
            Text(install.subject?.inspection.name ?? install.spec),
            if (install.subject?.inspection.version != null)
              pluginStatus(
                context,
                t('installVersion', {
                  'version': install.subject!.inspection.version,
                }),
              ),
            if (install.phase == PluginInstallPhase.unknown)
              pluginStatus(context, t('installUnknownDescription')),
            if (install.phase == PluginInstallPhase.unconfirmed ||
                (install.phase == PluginInstallPhase.applying &&
                    install.uncertainty != null))
              pluginStatus(
                context,
                t(
                  install.uncertainty == 'acceptance'
                      ? 'installAwaitingAcceptance'
                      : install.uncertainty == 'cancellation'
                      ? 'installCancelUnconfirmed'
                      : 'installResultUnconfirmed',
                  {'reason': install.error ?? ''},
                ),
              ),
            if (install.result?.error case final error?)
              pluginStatus(
                context,
                managementErrorText(
                  error.code.value,
                  error.diagnostic,
                  widget.i18n,
                ),
              ),
            if (install.phase == PluginInstallPhase.failed)
              pluginStatus(
                context,
                t(switch (install.result?.packageResult?.kind?.value) {
                  'pnpm-missing' => 'installFailurePnpmMissing',
                  'timeout' => 'installFailureTimeout',
                  'network' => 'installFailureNetwork',
                  'not-found' => 'installFailureNotFound',
                  'no-matching-version' => 'installFailureNoMatchingVersion',
                  'disk-full' => 'installFailureDiskFull',
                  'permission' => 'installFailurePermission',
                  'build-blocked' => 'installFailureBuildBlocked',
                  'integrity' => 'installFailureIntegrity',
                  _ => 'installFailureGeneric',
                }),
              ),
            if (install.restartRequired)
              pluginStatus(
                context,
                t('installDoneRestart', {
                  'reason': install.result?.restartReason?.value ?? '',
                }),
              ),
            if (install.totalAttempts > 0)
              pluginStatus(
                context,
                t('installAttemptBadge', {
                  'index': install.attemptedRegistries.length,
                  'registry':
                      install.attemptedRegistries.lastOrNull ??
                      t('registryDefault'),
                }),
              ),
            DshButton(
              onPressed: () => install.setDetails(!install.detailsOpen),
              child: Text(
                t(
                  install.detailsOpen
                      ? 'installDetailsHide'
                      : 'installDetailsShow',
                ),
              ),
            ),
            if (install.detailsOpen) ...[
              for (final run in install.runs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DshTerminalBlock(
                    command: run.command,
                    cwd: run.cwd,
                    output: run.output,
                    running: !run.settled,
                    exitCode: run.exitCode,
                    exitCodeMissing: run.settled && run.exitCode == null,
                    maxLines: 16,
                    labels: DshTerminalLabels(
                      commandLine: (n) => t('terminalCommandLine', {'n': n}),
                      signal: (s) => t('terminalSignal', {'signal': s}),
                      exitCode: (n) => t('terminalExitCode', {'code': n}),
                      noExitCode: t('terminalNoExitCode'),
                      running: t('terminalRunning'),
                      failed: t('terminalFailed'),
                      done: t('terminalDone'),
                      copy: t('terminalCopy'),
                      copied: t('terminalCopied'),
                      noOutput: t('terminalNoOutput'),
                      collapse: t('terminalCollapse'),
                      expand: (n) => t('terminalExpand', {'n': n}),
                    ),
                  ),
                ),
              if (install.runs.isEmpty)
                if (install.result?.packageResult?.output
                    case final String output)
                  pluginStatus(context, output),
            ],
          ],
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (editing)
                DshButton(
                  variant: DshButtonVariant.primary,
                  onPressed:
                      install.phase == PluginInstallPhase.checking ||
                          install.spec.trim().isEmpty
                      ? null
                      : () => unawaited(install.install()),
                  child: Text(t('installRun')),
                ),
              if (install.cancellable)
                DshButton(
                  onPressed: () => unawaited(install.cancel()),
                  child: Text(t('installCancel')),
                ),
              if (install.phase == PluginInstallPhase.unconfirmed ||
                  install.phase == PluginInstallPhase.applying)
                DshButton(
                  onPressed: () => unawaited(install.reconcile()),
                  child: Text(t('installReconcile')),
                ),
              if (install.githubRecovery != null)
                DshButton(
                  onPressed: install.recoverGithub,
                  child: Text(t('installUseGithubMirror')),
                ),
              if (install.phase == PluginInstallPhase.failed &&
                  install.pendingBuilds.isNotEmpty)
                DshButton(
                  onPressed: () => unawaited(_approve()),
                  child: Text(t('installApproveAndRetry')),
                ),
              if (install.phase == PluginInstallPhase.failed ||
                  install.phase == PluginInstallPhase.unknown)
                DshButton(
                  onPressed: () => unawaited(install.cancel()),
                  child: Text(t('installEdit')),
                ),
              if (install.phase == PluginInstallPhase.done &&
                  install.subject?.selection == null &&
                  install.installed != null)
                DshButton(
                  variant: DshButtonVariant.primary,
                  onPressed: install.enabling
                      ? null
                      : () async {
                          await install.enableInstalled();
                          if (context.mounted) Navigator.of(context).pop();
                        },
                  child: Text(t('installEnableNow')),
                ),
              if (install.phase == PluginInstallPhase.done)
                DshButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t('installClose')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
