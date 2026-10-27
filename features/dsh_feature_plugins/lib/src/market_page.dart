import 'dart:async';

import 'package:dsh_client/generated_plugin_market.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'common.dart';

class PluginMarketPage extends StatefulWidget {
  const PluginMarketPage({
    super.key,
    required this.model,
    required this.manager,
    required this.i18n,
    required this.onInstall,
  });
  final PluginMarketModel model;
  final PluginManagerModel manager;
  final DshI18n i18n;
  final VoidCallback onInstall;
  @override
  State<PluginMarketPage> createState() => _PluginMarketPageState();
}

class _PluginMarketPageState extends State<PluginMarketPage> {
  StreamSubscription<int>? _sub;
  PluginMarketModel get model => widget.model;
  String t(String key, [Map<String, Object?> p = const {}]) =>
      widget.i18n.t('pluginMarket', key, params: p);
  @override
  void initState() {
    super.initState();
    _sub = model.changed.changes.listen((_) {
      if (mounted) setState(() {});
    });
    scheduleMicrotask(model.ensure);
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  Future<void> _install(
    MarketListingEntry entry,
    MarketListingVersion version,
  ) async {
    final name = pluginText(entry.title, widget.i18n, entry.name);
    final yes = await showDshDialog<bool>(
      context,
      width: 480,
      label: t('confirmTitle', {'name': name}),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            pluginHeading(context, t('confirmTitle', {'name': name})),
            const SizedBox(height: 12),
            Text('${entry.name}@${version.version}'),
            ..._source(context, version),
            const SizedBox(height: 12),
            pluginStatus(context, t('installTrust')),
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
                  child: Text(t('install')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (yes != true || !mounted) return;
    final started = widget.manager.installer.show(
      installSpec: version.install.spec,
      transientRegistry: version.install.registry,
      confirmed: true,
    );
    if (started) unawaited(widget.manager.installer.install());
    widget.onInstall();
  }

  List<Widget> _source(BuildContext context, MarketListingVersion version) =>
      switch (version.source) {
        MarketSourceNpm(:final registry) => [
          pluginStatus(context, version.install.spec),
          if (registry != null) pluginStatus(context, registry),
        ],
        MarketSourceGit(:final url, :final commit, :final path) => [
          pluginStatus(context, url),
          pluginStatus(context, commit),
          if (path != null) pluginStatus(context, path),
        ],
        _ => [pluginStatus(context, version.install.spec)],
      };
  Future<void> _details(MarketListingEntry entry) async {
    final title = pluginText(entry.title, widget.i18n, entry.name);
    await showDshDialog<void>(
      context,
      width: 680,
      label: title,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: pluginHeading(context, title)),
                DshButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t('close')),
                ),
              ],
            ),
            pluginStatus(context, pluginText(entry.description, widget.i18n)),
            const SizedBox(height: 16),
            pluginHeading(context, t('versionsTitle')),
            for (final version in entry.versions)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: pluginCard(
                  context,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(version.version),
                      if (version.version == entry.defaultVersion)
                        pluginStatus(context, t('versionDefault')),
                      if (!version.compatibility.compatible)
                        pluginStatus(context, t('versionIncompatible')),
                      if (version.compatibility.exempted == true)
                        pluginStatus(context, t('versionExempted')),
                      ..._source(context, version),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: DshButton(
                          onPressed:
                              version.compatibility.compatible ||
                                  version.compatibility.exempted == true
                              ? () async {
                                  Navigator.of(context).pop();
                                  await _install(entry, version);
                                }
                              : null,
                          child: Text(t('install')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _query({
    String? category,
    bool clearCategory = false,
    List<String>? labels,
    MarketSort? sort,
  }) => model.search(
    PluginDiscoverQuery(
      text: model.listing?.query.text ?? '',
      category: clearCategory
          ? null
          : category ?? model.listing?.query.category,
      labels: labels ?? model.listing?.query.labels ?? const [],
      sort: sort ?? model.listing?.query.sort ?? const MarketSortIndex(),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final listing = model.listing, value = model.listing?.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final index in model.indexes)
              DshButton(
                size: DshButtonSize.sm,
                variant: index.url == model.selected
                    ? DshButtonVariant.toolbar
                    : DshButtonVariant.ghost,
                onPressed: () => unawaited(model.select(index.url)),
                child: Text(pluginText(index.title, widget.i18n, index.url)),
              ),
            DshButton(
              size: DshButtonSize.sm,
              onPressed: model.toggleSources,
              child: Text(t('manageSources')),
            ),
            if (listing != null)
              DshButton(
                size: DshButtonSize.sm,
                onPressed: () => unawaited(model.refresh()),
                child: Text(t('refresh')),
              ),
          ],
        ),
        if (model.status == PluginDiscoverStatus.loading)
          pluginStatus(context, t('loading')),
        if (model.status == PluginDiscoverStatus.error) ...[
          pluginStatus(context, t('sourcesFailed')),
          DshButton(
            onPressed: () => unawaited(model.loadIndexes()),
            child: Text(t('retry')),
          ),
        ],
        if (model.showSources) ...[
          const SizedBox(height: 16),
          pluginHeading(context, t('sourcesTitle')),
          pluginStatus(context, t('sourcesDescription')),
          for (final index in model.indexes)
            Row(
              children: [
                Expanded(child: pluginStatus(context, index.url)),
                DshButton(
                  onPressed: model.saving
                      ? null
                      : () => unawaited(model.removeSource(index.url)),
                  child: Text(t('removeSource')),
                ),
              ],
            ),
          const SizedBox(height: 8),
          PluginInput(
            value: model.draft,
            label: t('sourceUrl'),
            enabled: !model.saving,
            onChanged: model.editDraft,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: DshButton(
              onPressed: model.saving || model.draft.trim().isEmpty
                  ? null
                  : () => unawaited(model.addSource()),
              child: Text(t('addSource')),
            ),
          ),
          if (model.sourceFailure != null)
            pluginStatus(
              context,
              t(switch (model.sourceFailure) {
                'invalid' => 'sourceInvalid',
                'duplicate' => 'sourceDuplicate',
                'unavailable' => 'sourceUnavailable',
                _ => 'sourceFailed',
              }),
            ),
          pluginStatus(context, t('sourcesTrust')),
          const SizedBox(height: 24),
        ],
        if (model.status == PluginDiscoverStatus.ready &&
            model.indexes.isEmpty) ...[
          pluginHeading(context, t('emptyTitle')),
          pluginStatus(context, t('emptyDescription')),
        ],
        if (listing != null) ...[
          const SizedBox(height: 16),
          PluginInput(
            value: listing.query.text,
            label: t('search'),
            onChanged: (text) =>
                unawaited(model.search(listing.query.withText(text))),
          ),
          const SizedBox(height: 12),
          if (value?.metadata.categories.isNotEmpty == true)
            Semantics(
              container: true,
              explicitChildNodes: true,
              label: t('categoriesLabel'),
              child: Wrap(
                spacing: DshPillRecipe.categoryGap,
                runSpacing: DshPillRecipe.categoryGap,
                children: [
                  DshPill(
                    key: const ValueKey('market-category-all'),
                    active: listing.query.category == null,
                    pressed: listing.query.category == null,
                    onPressed: () => unawaited(_query(clearCategory: true)),
                    child: DshChromeText(t('allCategories')),
                  ),
                  for (final entry in value!.metadata.categories.entries)
                    DshPill(
                      key: ValueKey('market-category-${entry.key}'),
                      active: listing.query.category == entry.key,
                      pressed: listing.query.category == entry.key,
                      onPressed: () => unawaited(_query(category: entry.key)),
                      child: DshChromeText(
                        pluginText(entry.value.title, widget.i18n, entry.key),
                      ),
                    ),
                ],
              ),
            ),
          if (value?.metadata.labels.isNotEmpty == true)
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final entry in value!.metadata.labels.entries)
                  DshButton(
                    size: DshButtonSize.sm,
                    variant: listing.query.labels.contains(entry.key)
                        ? DshButtonVariant.toolbar
                        : DshButtonVariant.ghost,
                    onPressed: () => unawaited(
                      _query(
                        labels: listing.query.labels.contains(entry.key)
                            ? listing.query.labels
                                  .where((l) => l != entry.key)
                                  .toList()
                            : [...listing.query.labels, entry.key],
                      ),
                    ),
                    child: Text(
                      pluginText(entry.value.title, widget.i18n, entry.key),
                    ),
                  ),
              ],
            ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              DshButton(
                size: DshButtonSize.sm,
                onPressed: () =>
                    unawaited(_query(sort: const MarketSortIndex())),
                child: Text(t('sortDefault')),
              ),
              if (listing.query.text.trim().isNotEmpty)
                DshButton(
                  size: DshButtonSize.sm,
                  onPressed: () =>
                      unawaited(_query(sort: const MarketSortRelevance())),
                  child: Text(t('sortRelevance')),
                ),
              DshButton(
                size: DshButtonSize.sm,
                onPressed: () => unawaited(
                  _query(
                    sort: const MarketSortPublished(
                      direction: MarketSortPublishedDirection.desc,
                    ),
                  ),
                ),
                child: Text(t('sortPublished')),
              ),
              for (final entry
                  in value?.metadata.sortKeys.entries ??
                      const <MapEntry<String, MarketSortKeyDeclaration>>[])
                DshButton(
                  size: DshButtonSize.sm,
                  onPressed: () => unawaited(
                    _query(
                      sort: MarketSortKey(
                        id: entry.key,
                        direction: entry.value.order.value == 'asc'
                            ? MarketSortKeyDirection.asc
                            : MarketSortKeyDirection.desc,
                      ),
                    ),
                  ),
                  child: Text(
                    pluginText(entry.value.title, widget.i18n, entry.key),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (listing.status == PluginListingStatus.loading ||
              listing.status == PluginListingStatus.more)
            pluginStatus(context, t('loading')),
          if (listing.status == PluginListingStatus.error)
            Row(
              children: [
                Expanded(
                  child: pluginStatus(
                    context,
                    t(switch (listing.failure) {
                      'invalid' => 'readInvalid',
                      'changed' => 'readChanged',
                      _ => 'readFailed',
                    }),
                  ),
                ),
                DshButton(
                  onPressed: () => unawaited(model.retry()),
                  child: Text(t('retry')),
                ),
              ],
            ),
          if (value != null && value.entries.isEmpty)
            pluginStatus(
              context,
              t(value.total == 0 ? 'noMatches' : 'emptyIndex'),
            ),
          for (final entry in value?.entries ?? const <MarketListingEntry>[])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: pluginCard(
                context,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DshButton(
                            onPressed: () => unawaited(_details(entry)),
                            child: Text(
                              pluginText(entry.title, widget.i18n, entry.name),
                            ),
                          ),
                          pluginStatus(
                            context,
                            pluginText(entry.description, widget.i18n),
                          ),
                          pluginStatus(context, entry.name),
                          pluginStatus(
                            context,
                            widget.i18n.t(
                              'pluginMarket',
                              switch (entry.installation.status.value) {
                                'installed' => 'statusInstalled',
                                'provided' => 'statusProvided',
                                'update-available' => 'statusUpdate',
                                'different-version' => 'versionInstalled',
                                _ => 'install',
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    DshButton(
                      onPressed: () => unawaited(_details(entry)),
                      child: Text(t('versionsTitle')),
                    ),
                  ],
                ),
              ),
            ),
          if (value?.nextOffset != null)
            DshButton(
              onPressed:
                  listing.status == PluginListingStatus.more ||
                      listing.status == PluginListingStatus.loading
                  ? null
                  : () => unawaited(model.more()),
              child: Text(t('showMore')),
            ),
        ],
      ],
    );
  }
}
