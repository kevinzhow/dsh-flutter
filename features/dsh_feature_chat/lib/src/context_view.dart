import 'dart:convert';
import 'dart:math' as math;

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

Map<String, Object?>? _record(Object? value) =>
    value is Map<String, Object?> ? value : null;

/// Form selection is all-or-nothing: unreadable producer data stays opaque.
/// Never show a confident partial list in place of the model-facing content.
String? resolvedContextForm(MessageData data) {
  final s = data.source;
  bool list(
    String key,
    bool Function(Map<String, Object?>) valid, {
    bool empty = false,
  }) {
    final value = s?[key];
    return value is List &&
        (empty || value.isNotEmpty) &&
        value.every((e) => _record(e) != null && valid(_record(e)!));
  }

  bool named(Map<String, Object?> m, String key) =>
      m[key] is String && (m[key] as String).isNotEmpty;
  return switch (data.form) {
    'instructions'
        when list(
          'changes',
          (m) =>
              named(m, 'path') &&
              const {'set', 'replace', 'remove'}.contains(m['action']),
        ) =>
      data.form,
    'catalog'
        when list(
          'entries',
          (m) => named(m, 'name') && m['description'] is String,
          empty: true,
        ) =>
      data.form,
    'snapshot'
        when list('sections', (m) => named(m, 'name') && m['text'] is String) =>
      data.form,
    'notice'
        when s?['summary'] is String && (s!['summary'] as String).isNotEmpty =>
      data.form,
    'relay'
        when s?['senderSessionId'] is String &&
            (s!['senderSessionId'] as String).isNotEmpty =>
      data.form,
    'recall'
        when list(
          'references',
          (m) =>
              named(m, 'label') &&
              m['retainedMessages'] is num &&
              m['omittedMessages'] is num &&
              m['truncated'] is bool,
        ) =>
      data.form,
    _ => null,
  };
}

class ContextInjectionView extends StatefulWidget {
  const ContextInjectionView({
    super.key,
    required this.data,
    required this.i18n,
    this.initiallyOpen = false,
  });
  final MessageData data;
  final DshI18n i18n;
  final bool initiallyOpen;
  @override
  State<ContextInjectionView> createState() => _ContextInjectionViewState();
}

class _ContextInjectionViewState extends State<ContextInjectionView> {
  late bool _open = widget.initiallyOpen;
  String t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t('chat', key, params: params);
  String bounded(String value) => value.length > 20000
      ? '${value.substring(0, 20000)}\n${t('json.truncated', {'total': value.length})}'
      : value;
  String stringify(Object? value) =>
      value is String ? value : jsonEncode(value);

  List<Widget> modelContent(BuildContext context, {bool unknownOnly = false}) {
    final runs = <Object>[];
    for (final block in widget.data.content) {
      final m = _record(block);
      if (m?['type'] == 'text') {
        if (unknownOnly) continue;
        final text = m?['text'] as String? ?? '';
        if (runs.lastOrNull is String) {
          runs[runs.length - 1] = '${runs.last}$text';
        } else {
          runs.add(text);
        }
      } else {
        runs.add({'block': block});
      }
    }
    return [
      for (final run in runs)
        if (run is! String || run.isNotEmpty)
          run is String
              ? text(context, run)
              : DshJsonBlock(
                  label: t('message.unknownBlock'),
                  payload: (run as Map)['block'],
                  truncatedLabel: (total) =>
                      t('json.truncated', {'total': total}),
                ),
    ];
  }

  Widget text(
    BuildContext context,
    String value, {
    bool caption = false,
    bool tertiary = false,
  }) => DshChromeText(
    bounded(value),
    style: context.dsh
        .fixedCodeStyle(size: 11, line: 16)
        .copyWith(
          color: caption
              ? context.dsh.color('--dsw-alias-label-caption')
              : tertiary
              ? context.dsh.color('--dsw-alias-label-tertiary')
              : context.dsh.labelSecondary,
        ),
  );

  Widget recallRow(
    BuildContext context,
    Map<String, Object?> reference,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final label = bounded(reference['label'] as String);
      final counts = t('message.context.recall.counts', {
        'retained': reference['retainedMessages'],
        'omitted': reference['omittedMessages'],
      });
      final truncated = reference['truncated'] == true
          ? t('message.context.recall.truncated')
          : null;
      final style = context.dsh.fixedCodeStyle(size: 11, line: 16);
      double measure(String value) {
        final painter = TextPainter(
          text: TextSpan(text: value, style: style),
          textDirection: Directionality.of(context),
        )..layout();
        final width = painter.maxIntrinsicWidth;
        painter.dispose();
        return width;
      }

      final countWidth = measure(counts),
          truncatedWidth = truncated == null ? 0.0 : measure(truncated);
      final fixed = countWidth + truncatedWidth + (truncated == null ? 8 : 16);
      final minimum = label.characters.map(measure).fold(0.0, math.max);
      final labelWidth = math.min(
        measure(label),
        math.max(minimum, constraints.maxWidth - fixed),
      );
      // CSS keeps the counts on one flex line and shrinks only the label. On
      // narrow screens that label can occupy one glyph per line.
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        primary: false,
        child: SizedBox(
          width: labelWidth + fixed,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: labelWidth, child: text(context, label)),
              const SizedBox(width: 8),
              SizedBox(
                width: countWidth,
                child: text(context, counts, caption: true),
              ),
              if (truncated != null) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: truncatedWidth,
                  child: text(context, truncated, caption: true),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );

  Widget body(
    BuildContext context,
    String? form,
    List<Map<String, Object?>>? tools,
  ) {
    final source = widget.data.source ?? const <String, Object?>{};
    final children = <Widget>[];
    if (tools != null) {
      for (final type in ['tool-addition', 'tool-removal']) {
        final names = tools
            .where((b) => b['type'] == type)
            .map((b) => b['toolName'])
            .join(', ');
        if (names.isNotEmpty) {
          children.add(
            text(
              context,
              t(
                type == 'tool-addition'
                    ? 'message.toolsAdded'
                    : 'message.toolsRemoved',
                {'names': names},
              ),
            ),
          );
        }
      }
    } else {
      switch (form) {
        case 'instructions':
          final seen = <String>{};
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  for (final raw in source['changes'] as List)
                    if (seen.add((raw as Map)['path'] as String))
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(child: text(context, raw['path'] as String)),
                          const SizedBox(width: 6),
                          text(
                            context,
                            t(
                              'message.context.instructions.${raw['action'] == 'remove'
                                  ? 'removed'
                                  : source['baseline'] == true
                                  ? 'loaded'
                                  : raw['action'] == 'set'
                                  ? 'added'
                                  : 'updated'}',
                            ),
                            caption: true,
                          ),
                        ],
                      ),
                ],
              ),
            ),
          );
          children.addAll(modelContent(context));
        case 'catalog':
          if (source['update'] == true) {
            children.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: text(
                  context,
                  t('message.context.catalog.replaced'),
                  caption: true,
                ),
              ),
            );
          }
          final entries = source['entries'] as List;
          for (var i = 0; i < math.min(200, entries.length); i++) {
            final entry = entries[i];
            children.add(
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == math.min(200, entries.length) - 1 ? 0 : 4,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    text(context, (entry as Map)['name'] as String),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DshChromeText(
                        bounded(entry['description'] as String),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.dsh
                            .fixedCodeStyle(size: 11, line: 16)
                            .copyWith(
                              color: context.dsh.color(
                                '--dsw-alias-label-tertiary',
                              ),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          if (entries.length > 200) {
            children.add(
              text(
                context,
                t('message.context.catalog.more', {
                  'count': entries.length - 200,
                }),
                caption: true,
              ),
            );
          }
          children.addAll(modelContent(context, unknownOnly: true));
        case 'snapshot':
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: text(
                context,
                t('message.context.snapshot.supersedes'),
                caption: true,
              ),
            ),
          );
          final sections = source['sections'] as List;
          for (var i = 0; i < sections.length; i++) {
            final section = sections[i] as Map;
            children.add(
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    text(context, section['name'] as String, caption: true),
                    const SizedBox(height: 2),
                    text(context, section['text'] as String),
                  ],
                ),
              ),
            );
          }
        case 'relay':
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: text(
                context,
                t('message.context.relay.from', {
                  'session': source['senderSessionId'],
                }),
                caption: true,
              ),
            ),
          );
          children.addAll(modelContent(context));
        case 'recall':
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (
                    var i = 0;
                    i < (source['references'] as List).length;
                    i++
                  )
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
                      child: recallRow(
                        context,
                        ((source['references'] as List)[i] as Map)
                            .cast<String, Object?>(),
                      ),
                    ),
                ],
              ),
            ),
          );
          children.addAll(modelContent(context));
        case 'notice':
          children.addAll(modelContent(context));
        default:
          children.addAll(modelContent(context));
          final fields = source.entries.where((e) => e.key != 'kind').toList();
          if (fields.isNotEmpty) {
            children.add(
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: context.dsh.color('--dsw-alias-border-l2'),
                        width: dshBorderWidthOf(context, .5),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: 8 + dshBorderWidthOf(context, .5),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < fields.length; i++)
                          Padding(
                            padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minWidth: 96,
                                  ),
                                  child: text(
                                    context,
                                    fields[i].key,
                                    caption: true,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: text(
                                    context,
                                    stringify(fields[i].value),
                                    tertiary: true,
                                  ),
                                ),
                              ],
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
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data, theme = context.dsh;
    final form = resolvedContextForm(data);
    final tools =
        data.content.isNotEmpty &&
            data.content.every(
              (b) =>
                  _record(b)?['type'] == 'tool-addition' ||
                  _record(b)?['type'] == 'tool-removal',
            )
        ? data.content.cast<Map<String, Object?>>()
        : null;
    final single = tools?.length == 1 ? tools!.single : null;
    final added = tools?.where((b) => b['type'] == 'tool-addition').length ?? 0;
    final removed = (tools?.length ?? 0) - added;
    final summary = tools != null && single == null
        ? t(
            added > 0 && removed > 0
                ? 'message.toolsChanged'
                : added > 0
                ? 'message.toolsAddedCount'
                : 'message.toolsRemovedCount',
            {
              'added': added,
              'removed': removed,
              'count': added > 0 ? added : removed,
            },
          )
        : tools == null && data.producerLabel != null
        ? [
            data.producerLabel!,
            if (form == 'notice') data.source!['summary'] as String,
          ].join(' · ')
        : null;
    void toggle() {
      DshDisclosureChange(!_open, context).dispatch(context);
      setState(() => _open = !_open);
    }

    return DshDisclosureRow(
      icon: tools != null
          ? DshIcons.browse
          : data.producerRole == 'recall'
          ? DshIcons.chatLines
          : DshIcons.contextInjection,
      title: single != null
          ? t(
              single['type'] == 'tool-addition'
                  ? 'message.toolAdded'
                  : 'message.toolRemoved',
              {'name': single['toolName']},
            )
          : t(
              tools != null
                  ? 'message.toolsUpdated'
                  : data.producerRole == 'recall'
                  ? 'message.contextRecall'
                  : 'message.contextInjection',
            ),
      open: _open && single == null,
      expandable: single == null,
      onToggle: toggle,
      chevronColor: theme.labelSecondary,
      collapsedContent: summary == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox.square(
                    dimension: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.color('--dsw-alias-label-caption'),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
      children: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 0, 4),
        child: ConstrainedBox(
          key: ValueKey('context-body-${form ?? 'opaque'}'),
          constraints: const BoxConstraints(maxHeight: 141),
          child: DshDecoratedBox(
            decoration: theme.cornerDecoration(
              theme.radiusMd,
              color: theme.color('--dsw-alias-markdown-code-block'),
            ),
            child: theme.clipCorners(
              theme.radiusMd,
              SingleChildScrollView(
                primary: false,
                padding: const EdgeInsets.fromLTRB(12, 10, 16, 12),
                child: body(context, form, tools),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
