/// Trigger detection (dsh `ui-input-trigger` `core/detect`): the `@` or `/`
/// token under the caret, with dsh's word-boundary rules.
library;

import 'file_reference_grammar.dart';
import 'trigger_types.dart';

final RegExp _wordChar = RegExp(r'[\p{L}\p{N}_]', unicode: true);
final RegExp _space = RegExp(r'\s', unicode: true);
final RegExp _nonSpace = RegExp(r'\S', unicode: true);

bool _isSpace(String ch) => _space.hasMatch(ch);

/// A trigger character opens only at the draft start, after whitespace
/// (newlines included) or after punctuation. Two URL carve-outs keep `/` dead
/// inside URLs: `/` after a `:` that itself follows a non-whitespace character
/// (`https:/...`), and `/` directly after another `/`.
bool _boundaryOk(String draft, int index, String char) {
  if (index == 0) return true;
  final prev = draft[index - 1];
  if (_isSpace(prev)) return true;
  if (_wordChar.hasMatch(prev)) return false;
  if (char == '/') {
    if (prev == '/') return false;
    if (prev == ':' && index >= 2 && !_isSpace(draft[index - 2])) return false;
  }
  return true;
}

/// Detect a trigger token at [caret] under [tier]. `@` first uses the shared
/// grammar (an open quoted token may span whitespace); `/` scans left to the
/// first whitespace, skipping slashes that fail the boundary rule. `claimed`
/// suppresses `/`; `frozen` suppresses both. The returned span carries a
/// placeholder revision `0`: the caller stamps the real one.
TriggerHit? detectTrigger(String draft, int caret, TriggerTier tier) {
  if (tier == TriggerTier.frozen) return null;
  final first = draft.indexOf(_nonSpace);
  final at = activeAtToken(draft, caret);
  if (at != null) {
    final start = caret - at.prefix.length;
    return TriggerHit(
      trigger: TriggerChar.at,
      query: at.query,
      quoted: at.quoted,
      position: first == start
          ? TriggerPosition.leading
          : TriggerPosition.inline,
      span: TokenSpan(start, caret, 0),
    );
  }
  for (var i = caret - 1; i >= 0; i--) {
    final ch = draft[i];
    if (_isSpace(ch)) return null;
    if (ch != '/') continue;
    if (tier == TriggerTier.claimed) continue;
    if (!_boundaryOk(draft, i, ch)) continue;
    return TriggerHit(
      trigger: TriggerChar.slash,
      query: draft.substring(i + 1, caret),
      quoted: false,
      position: first == i ? TriggerPosition.leading : TriggerPosition.inline,
      span: TokenSpan(i, caret, 0),
    );
  }
  return null;
}
