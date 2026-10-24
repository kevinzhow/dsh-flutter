/// Stream elements that dsh web does not have, ported from raft-flutter and
/// switched off until the owner asks for them: the skeleton placeholder
/// (while a session opens, and above the oldest row while a page is read) and
/// the "N new" count on the back-to-bottom control. With it off the stream
/// shows what dsh web shows: the "Loading history…" hint, the "Load earlier"
/// button, and the plain chevron.
///
/// Tests flip it; nothing else should.
bool streamExtras = false;
