# Design-system style literal audit — task20

The current guard does **not** establish compliance with Kevin's de915b41 directive. At primary commit `ac8d066aa10802679e5e7c3c1d897c1bea613981`, it counts899 legacy manual-metric matches,11 platform controls and4 duplicate-button uses, while allowing905 manual metrics. The exhaustive machine inventory is [design-system-style-literals-audit.json](design-system-style-literals-audit.json); it records every candidate's exact path, line, column, owner/symbol bucket, context/fingerprint, provenance and current ratchet treatment.

This is a read-only audit. No product/test/native/build/guard edits were made. Root owns task20, the generator/guard changes and integration. The pinned reference remains `687f282e8625c6b8d11ff58211a90524be2e4317`, released0.2.1-rc.2 packages. All87 UI Dart files were hashed (86src files and one export-only entrypoint), including7 generated artifacts. There are4032 lexical candidates/references. This is exhaustive **within the documented scanner**, not a claim that every number is styling or that every Dart expression has been semantically proved.

The scanner records numbers outside comments/strings, explicit color/style enums, color/font strings, generated recipe references, theme-token/getter references and DshSpace uses. SVG path strings are recorded as whole data+hash; interpolation inside strings is a documented lexical limitation. The JSON separately records all915 raw ratchet occurrences across apps/features/packages lib, including the one wrapper-suppressed occurrence. It also includes all current baselines, wrapper reasons, source file hashes, potential property/value leads and all family/package owner buckets. Potential equal CSS numbers are **leads only**, never individual provenance approval.

|Evidence bucket|Count|Meaning|
|---|---:|---|
|Generated recipe declarations|660|Generated values; extractor/source lock remain the authority|
|Generated recipe references|563|Every recorded class.field resolves; this does not prove extractor completeness|
|Generated token/getter references|316 +1dynamic|Known names; surrounding geometry may still be manual|
|Generated asset/table candidates|736|Separate source generators; not handwritten component styling|
|Source-matched handwritten style candidates|19|Individually checked values, still not generated|
|Source-matched artwork colors|8|Actual upstream SVG colors, not an invented palette|
|Untraced numeric style-context candidates|439|Require individual tracing; not automatically incorrect|
|Framework style/layout choice candidates|295|Require source/profile-role review; not automatically styling violations|
|Handwritten shared aliases/references|25|7 DshSpace definitions and18 canonical uses|
|Other structural/layout numeric candidates|623|Unresolved role; cannot honestly call all of them style|
|Fitted sigma / fixed clip extent candidates|3 /4|Concrete renderer mismatch and untraced paint bounds, detailed below|

The JSON contains the full remaining algorithm/representation buckets.759 style/choice/alias candidates still lack an individual trace, and636 of those occur on lines outside the current manual-metric rule. These are triage counts, **not759 proven violations**.115 of the existing899 metric matches are in dsh_ui itself; their stored allowance is120.

The current per-file guard has two concrete gaps beyond its acknowledged legacy debt. Its manual-metric regex checks only height/width/fontSize/radius/horizontalPadding/size/gap/decorationThickness numeric arguments plus numeric BorderRadius.circular. It does not cover EdgeInsets positional/named values, durations, opacity, colors, font-weight enums, max/min dimensions or shared numeric constants. Equal counts also let one old value be replaced by an unrelated value in the same file. The unused allowance is5 slots in dsh_settings.dart (20allowed/15actual) and1 in features/dsh_feature_commands/lib/src/popup_view.dart (11/10). The current count policy has no violations, which is a statement about the policy, not the directive.

The platform-control allowlist suppresses the **whole rule** for dsh_text_field.dart and dsh_settings.dart, not just a named native text editor or a fixed occurrence. Currently only TextField at dsh_text_field.dart:76 is suppressed; dsh_settings.dart has no current platform-control match, but its exemption remains. The machine report preserves that raw occurrence, the exact reason and the dormant broad exception. Baseline entries carry counts/remediation, not literal-specific source provenance.

The family inventory declares16 families and27 canonical files across the workspace;24 of those files are in dsh_ui. The other UI files include valid helpers and generated assets as well as unlisted content components, so absence from the list is an ownership/provenance gap, not automatic visual failure. Largest pending candidate groups are:

|UI source file|Candidates still needing style/choice/alias trace|
|---|---:|
|packages/dsh_ui/lib/src/dsh_attachment.dart|96|
|packages/dsh_ui/lib/src/dsh_settings.dart|50|
|packages/dsh_ui/lib/src/dsh_settings_form.dart|41|
|packages/dsh_ui/lib/src/dsh_terminal_block.dart|38|
|packages/dsh_ui/lib/src/dsh_guide.dart|31|
|packages/dsh_ui/lib/src/dsh_web_block.dart|30|
|packages/dsh_ui/lib/src/dsh_lightbox.dart|28|
|packages/dsh_ui/lib/src/dsh_search_block.dart|28|

Concrete provenance distinctions prevent a blanket “all constants are wrong” result:

- Toast's3000/1000ms hold/fade match actual Toast.tsx,160ms entry/top40px/max640px/12×16px padding/gap10/14px-on22px copy match Toast.module.css, and its24px sides derive from the source48px viewport inset. Those are real source-defined values, but they remain manually copied without a generated Toast recipe. The exact source lines/hashes are in the JSON. Its icon16px has not been individually traced merely because other source metrics also contain16.
- Frame clearances48/160/84 and Windows content radius16 match exact AppFrame.module.css custom properties. They remain manual Flutter constants. The40px Windows caption default was not upgraded to a verified match merely because several tests set a40px custom property.
- DshGuide's fixed blue/yellow/terminal/default-gradient colors match plugin-artwork.tsx, guide-artwork.tsx and terminal.tsx SVG attributes. They belong to source artwork rather than an arbitrary theme palette. Asset provenance/generation is still a separate need.
- DshSpace centralizes4/8/12/16/24/44/760, but no global source spacing-token contract was established for those aliases. Repeated equal values in different component sheets do not justify a universal alias. Per-family source extraction is required.
- Device-pixel snapping, normalized/clamped layout bounds, font-leading rounding, font-weight enum conversion, saturate matrices, image header parsing and SVG coordinates are distinct from authored style values. Renderer/data/approximation buckets retain their proof confidence and limits. The local48-segment curve approximation is explicit numerical implementation debt, not silently labelled generated styling.

The shadow finding is verified against immutable renderer sources. Chromium145.0.7632.6 resolves to commit47e20adcc15fc15f01825aa17e570c8f5492ac0f; its DEPS pins Skia2ab8add5be2c46eb6238f4c217f6d6dbc9bccd23. CSS shadow radius follows `ShadowData::BlurRadiusToStdDev` → `BlurAsSigma` → box painter → draw looper; it uses sigma=radius/2. Skia's separate legacy radius converter uses0.57735×radius+0.5, and Flutter Shadow uses that legacy formula. These are real renderer algorithms; their constants must not be treated as arbitrary style. The local `_chromiumSigma` at dsh_shadow_box.dart:49 instead uses max(0.5,0.45×blur−2.1), and its own lines44–48 explicitly describe fitting. For blur8/16 it gives1.5/5.1, while pinned Blink gives4/8. This parameter mismatch is concrete. Low-alpha raster quantization may affect visible tails; it does not create that alternative input-sigma formula in the traced code.

The same painter bounds its outside path with fixed−200/+400 values at line69. No offset/spread/blur derivation was found. Pinned Skia computeFastBounds outsets by3×sigma; the source files and hashes are:

|Immutable source|SHA256|Relevant source lines|
|---|---|---|
|https://chromium.googlesource.com/chromium/src/+/47e20adcc15fc15f01825aa17e570c8f5492ac0f/DEPS|6ee25b372416426fcefc7063d44e81bf39fc58d699b0b2e8b3f8dabce5c57901|315|
|https://chromium.googlesource.com/chromium/src/+/47e20adcc15fc15f01825aa17e570c8f5492ac0f/third_party/blink/renderer/core/style/shadow_data.h|8a4f620e196502c3f9cd1188bebe92e42092ac9dbce3bb7e93ce639dfd07f563|76,81,89|
|https://chromium.googlesource.com/chromium/src/+/47e20adcc15fc15f01825aa17e570c8f5492ac0f/third_party/blink/renderer/core/paint/box_painter_base.cc|bb6718a8cb3885693a35ec51b14cae7c44ab1f26d518e27fab4ca077d3bd9995|333,459|
|https://chromium.googlesource.com/chromium/src/+/47e20adcc15fc15f01825aa17e570c8f5492ac0f/third_party/blink/renderer/platform/graphics/draw_looper_builder.cc|2d5716a4311e318aed91aa46fdcebf9c7b25f60774a9cd5b191ebe767377d8fa|54,75|
|https://chromium.googlesource.com/skia/+/2ab8add5be2c46eb6238f4c217f6d6dbc9bccd23/src/core/SkBlurMask.cpp|eb47eaff9958c5cd44f897d6c80d939bc2e1a6caa2b49f5cb4703e6e4d90866e|35,38|
|https://chromium.googlesource.com/skia/+/2ab8add5be2c46eb6238f4c217f6d6dbc9bccd23/src/core/SkBlurMaskFilterImpl.cpp|fa016f565411ed91798f87ab756124f43df241e96b055fa254b5b2c91786f2da|51,111,571,574,598|
|[workspace]/toolchains/flutter-3.47.6/engine/src/flutter/lib/ui/painting.dart|9858458e34b236815023634099223d845fe13f38bc309f330605fc5ad7a93e9e|8712,8713|

The complete correction plan/test contract is also machine-readable as shadowCorrectionPlan. It is **plan only**; root will implement a separate runtime batch after generator/guard tightening:

1. Treat the input BoxShadow blurRadius as the source CSS radius, with sigma=radius/2 and zero blur unfiltered. Keep all generated offsets, spreads, colors, corner radii and CSS layer order. Add no theme/alpha-specific adjustment.
2. Replace the fixed outside reach with a bound derived from the actual shifted/spread shape and its3×sigma fast bounds, unioned with the outer card and constrained by the real canvas/ancestor clip. Account for CTM/device rounding using renderer rules, without an invented padding value. Preserve the rule that shadows never show through the translucent interior.
3. Establish RED/GREEN conversion checks for source blur8→sigma4 and16→8, plus zero blur. Capture actual pinned MenuSurface and another real DshShadowBox consumer using published low-alpha multi-layer shadows in both themes and DPR1/2.625. Source screenshots are acceptance; old Flutter images only show what changed.
4. Verify exterior-only paint beneath translucent fill, layer order, rounded shape and ancestor clipping. Include large offset/spread/blur that legitimately reaches past200px, mirrored negative offsets and negative-spread/empty-outline behavior so the old fixed cutoff cannot hide. Keep the existing corner approximation as separately tracked debt during this batch.

Exact source conversion does not promise pixel identity across every Skia fast path. Record residuals, then investigate the renderer mechanism; never refit sigma to a score. Root owns full checks, builds, native replay, evidence and final acceptance. Overall visual99.5 remains unfinished.
