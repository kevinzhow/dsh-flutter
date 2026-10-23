/// Theme contract engine: pack JSON -> parse / validate / inherit -> [DshThemeData].
///
/// The vocabulary is dsh's own `--dsw-*` token names (leading `--` kept, exactly
/// as the dsh stylesheets write them). The official pack is generated from those
/// stylesheets by `tool/theme-adapters/build_official_pack.py`; a user pack loads
/// through the same [ThemePack.parse] / [ThemePack.fromJson] path.
library;

export 'src/color_value.dart';
export 'src/contract_names.g.dart'
    show dshContractKinds, dshContractNames, dshPackFontRoles;
export 'src/dsh_theme_data.dart';
export 'src/gradient_value.dart';
export 'src/official_pack.dart';
export 'src/official_pack.g.dart' show officialPackData;
export 'src/resolve_theme.dart';
export 'src/shadow_value.dart' show ShadowValue;
export 'src/theme_exception.dart';
export 'src/theme_pack.dart';
export 'src/theme_settings.dart';
export 'src/typography_value.dart';
