import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'dsh_icon.dart';
import 'dsh_icons.g.dart';
import 'dsh_markdown.dart';
import 'dsh_text_scale.dart';
import 'theme_access.dart';

class DshWebSource {
  const DshWebSource({
    required this.url,
    this.title,
    this.snippet,
    this.publishedAt,
  });
  final String url;
  final String? title;
  final String? snippet;
  final String? publishedAt;
}

class DshWebLabels {
  const DshWebLabels({
    required this.noResults,
    required this.sourcesTruncated,
    required this.http,
    required this.contentTruncated,
  });
  final String noResults;
  final String sourcesTruncated;
  final String http;
  final String contentTruncated;
}

/// The http(s) form of [url], or null for another scheme or an unparsable one.
Uri? safeWebUri(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  return uri.scheme == 'http' || uri.scheme == 'https' ? uri : null;
}

String _linkLabel(String url, String? title) {
  if (title != null && title.isNotEmpty) return title;
  final host = Uri.tryParse(url)?.host ?? '';
  return host.isEmpty ? url : host;
}

/// Web search sources or a fetch summary (dsh `WebBlock`). Links are handed to
/// [onOpenUrl]; this package opens nothing itself.
class DshWebBlock extends StatelessWidget {
  const DshWebBlock.search({
    super.key,
    required this.sources,
    required this.truncated,
    required this.labels,
    required this.onOpenUrl,
    this.answer,
  }) : url = null,
       statusCode = null;

  const DshWebBlock.fetch({
    super.key,
    required String this.url,
    required int this.statusCode,
    required this.truncated,
    required this.labels,
    required this.onOpenUrl,
  }) : sources = null,
       answer = null;

  final String? answer;
  final List<DshWebSource>? sources;
  final String? url;
  final int? statusCode;
  final bool truncated;
  final DshWebLabels labels;
  final void Function(Uri url) onOpenUrl;

  Widget _link(
    BuildContext context,
    String targetUrl,
    String label,
    TextStyle style, {
    bool icon = true,
  }) {
    final theme = context.dsh;
    final uri = safeWebUri(targetUrl);
    final linkStyle = style.copyWith(color: theme.color('--dsw-alias-link'));
    if (uri == null) return Text(label, style: style);
    final size = (style.fontSize ?? 14) * 1.1;
    return Text.rich(
      TextSpan(
        children: [
          if (icon)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 5),
                child: DshIcon(
                  DshIcons.globe,
                  size: size,
                  color: theme.color('--dsw-alias-link'),
                ),
              ),
            ),
          TextSpan(
            text: label,
            style: linkStyle,
            recognizer: TapGestureRecognizer()..onTap = () => onOpenUrl(uri),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final small = theme.textStyle('--dsw-font-xs-13');
    final tertiary = theme.color('--dsw-alias-label-tertiary');
    final fill = theme.color('--dsw-alias-markdown-code-block');
    Widget card(Widget child) => DecoratedBox(
      key: const ValueKey('web-block'),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(theme.radiusLg),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: child,
      ),
    );

    if (url != null) {
      final code = theme.textStyle('--dsw-font-markdown-code');
      return card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _link(
              context,
              url!,
              url!,
              code.sized(13, line: 19).copyWith(fontWeight: FontWeight.w500),
              icon: true,
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${labels.http} $statusCode',
                  style: small.copyWith(color: theme.labelSecondary),
                ),
                if (truncated) ...[
                  const SizedBox(width: 12),
                  Text(
                    labels.contentTruncated,
                    style: small.copyWith(color: tertiary),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    }

    final list = sources!;
    final hasAnswer = answer != null && answer!.isNotEmpty;
    final empty = !hasAnswer && list.isEmpty;
    final body = theme.textStyle('--dsw-font-s-14');
    return card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasAnswer) ...[
            DshMarkdown(answer!),
            if (!empty) const SizedBox(height: 8),
          ],
          if (empty)
            Text(
              labels.noResults,
              style: small.copyWith(color: theme.labelSecondary),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < list.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 34,
                            child: Text(
                              '${i + 1}.',
                              textAlign: TextAlign.right,
                              style: body.copyWith(
                                height: 20 / 14,
                                color: theme.labelPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _link(
                                  context,
                                  list[i].url,
                                  _linkLabel(list[i].url, list[i].title),
                                  body.copyWith(
                                    fontWeight: FontWeight.w500,
                                    height: 20 / 14,
                                  ),
                                ),
                                if (list[i].snippet != null &&
                                    list[i].snippet!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      list[i].snippet!,
                                      style: body
                                          .sized(13, line: 19)
                                          .copyWith(
                                            color: theme.labelSecondary,
                                          ),
                                    ),
                                  ),
                                if (list[i].publishedAt != null &&
                                    list[i].publishedAt!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      list[i].publishedAt!,
                                      style: small.copyWith(color: tertiary),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (truncated)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                labels.sourcesTruncated,
                style: small.copyWith(color: tertiary),
              ),
            ),
        ],
      ),
    );
  }
}
