/// Reference feature (dsh `ui-reference`): the `@` source for file, folder and
/// session references, their codec, and the registration into the trigger
/// pipeline. File and session picks insert atomic chips whose serialized form
/// is the natural `@path` text or the canonical `@[label](dsh-session:...)`
/// mention.
library;

export 'src/reference_source.dart';
export 'src/register.dart';
