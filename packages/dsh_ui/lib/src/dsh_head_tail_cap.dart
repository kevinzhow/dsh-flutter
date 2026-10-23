/// Head/tail split metrics for a capped list (dsh `headTailCap`).
class HeadTailCap {
  const HeadTailCap({
    required this.hidden,
    required this.capped,
    required this.headLines,
    required this.tailLines,
  });

  /// Rows beyond the cap; zero or less means nothing is hidden.
  final int hidden;

  /// Over the cap and not expanded: the list shows a head and a tail slice.
  final bool capped;
  final int headLines;
  final int tailLines;
}

HeadTailCap headTailCap(int total, int maxLines, bool expanded) {
  final hidden = total - maxLines;
  final head = (maxLines / 2).ceil();
  return HeadTailCap(
    hidden: hidden,
    capped: hidden > 0 && !expanded,
    headLines: head,
    tailLines: maxLines - head,
  );
}
