import 'official_pack.g.dart';
import 'theme_pack.dart';

/// Id of the built-in official pack.
const String officialPackId = 'official';

/// The official dsh look: [officialPackData] (generated from dsh's stylesheets)
/// parsed by the same [ThemePack.fromJson] a user pack goes through.
final ThemePack officialPack = ThemePack.fromJson(officialPackData);

/// Packs a user pack may extend without shipping them (`"extends": "official"`).
final Map<String, ThemePack> builtInPacks = {officialPackId: officialPack};
