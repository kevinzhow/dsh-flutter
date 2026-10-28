# Published loaded package cards

This bounded migration replaces the loaded PluginManager package card and list
presentation with `DshPluginCard`/`DshPluginCardList`, plus the canonical Tag's
`pluginStatus` profile. It removes the 12 metric matches in `_grid`/`_card`:
892 → 880 globally, with the other 31 manager-file matches retained. Generic
DshCard, official configuration ItemCard and the rest of PluginManager remain
separate pending consumers. This is not a claim of complete card-family or
overall visual parity.

The source is the integrity-verified published plugin-manager 0.2.1-rc.2 bundle,
reference commit `687f282e8625c6b8d11ff58211a90524be2e4317`. Its loaded
CardHead/PackageCard/PackageArtwork/EnableSwitch and presentation predicates are
locked by the companion source-contract change. Recipes own all new metrics
and style tokens, including the experimental package-name prefix. No source
factory body or CSS is rewritten to produce the reference.

The source-only audit and actual Chromium geometry/behavior evidence are in
the integrator's `notes/plugin-card-source-audit.md` and isolated
`scratch/plugin-card-source-audit/`. They cover light/dark, desktop/phone,
English/Chinese and DPR 1/2.625. Source-only assertions do not establish that
the Flutter implementation passes paired pixel or native acceptance.

## Canonical presentation and input

The head lays out naturally: 48px content-box artwork frame plus the source
border, 36px default/image artwork, generated head padding/gap, a wrapping
title/tag row and optional one-line description. There is no fixed card height.
The 14px gap before the switch belongs to cardHead; the 8px end gap separates
multiple trailing controls. Status tags retain canonical palettes and border
behavior, with the source's separate 18px content-height profile. Outline tags
therefore remain taller than filled tags by their border widths.

`DshPluginCardCanvas` reserves the negative source margins in the actual page
ancestor layout. `DshPluginCardInset` keeps ordinary headings, tabs, notices
and detail content aligned where they were. Card lists use the reserved space,
so their side targets can receive input through Flutter's ancestors. This is
different from merely painting an OverflowBox outside an unhittable parent.
The original page constraints/insets remain the existing feature-owned values;
only the generated card margin is added/subtracted to rebalance the layout.

The source title action is implemented through the shared DshButton input/focus
owner's bounded `pluginCard` profile. Its painted action covers the card. The
presentation and trailing controls are siblings above that target, so a
disabled switch absorbs its own input without opening the package. A source
contour hit test rejects the clipped corner without clipping the outer focus
outline. Title and switch keep independent native semantics, tap actions and
keyboard focus. The description is the action's accessible hint; tags and the
metadata live region remain separate content.

Card hover belongs to the containing card, including when the pointer is over
its switch. The external hover input is restricted to the source card profile;
unrelated primitive/add/info/icon/Header profiles retain their predicates and
geometry. Translucent descendants are composited against the hover ground
only when it is known opaque. An unknown backdrop remains translucent.

`image` is presentation data supplied as an ImageProvider. The feature adapts
metadata URLs with NetworkImage; the canonical component owns size, fit,
fallback and provider-identity reset. Failed providers keep the fallback while
unchanged; a new provider can recover. This does not add native SVG decoding or
certify every format a browser img can display.

## Existing state adaptation

The feature continues to own host decisions and navigation. It now follows the
source's loaded-card branches:

- Package errors produce a Problem tag; metadata errors produce their own
  diagnostic line and do not revoke management permission.
- An off/error switch is locked unless a missing package has an install target
  for recovery. Busy/read-only cases remain locked. An enabled problem package
  can still be disabled.
- Beta, missing and update tags use the source predicates. Update detection
  includes link-source changes and excludes installation/nonremovable cases.
- Description comes from localized metadata; absent/empty metadata does not
  invent a fallback package description.
- A refused toggle keeps the accepted switch state and never opens the card.

No install, detail, membership-filtering or host capability is introduced by
the canonical card. Parent list membership and other pending manager behavior
remain unchanged.

## Focused verification and limits

Four feature regressions were first run against the unchanged base and failed
for the existing source differences: switch locking, metadata ownership,
extended hit geometry and natural status wrapping. Their RED log is retained.
An additional RED caught unknown-backdrop alpha being incorrectly composited;
the fix preserves transparency. Canonical tests cover fractional-DPR content
boxes/status tags, source contour hits, pointer/keyboard/native actions,
independent switch focus, disabled absorption, hover ownership, wrapping and
image failure/recovery. Existing Button profiles and primitive Tag behavior
remain in the focused test set. A separate before/after geometry probe retains
eight ordinary page slots, including detail controls, from the pre-migration
base.

The integrator owns exact combined-source checks, paired captures and native
replay. The UI change depends on the companion generated recipe/source
contract; temporary local schema shims used during parallel development are
excluded from the UI commit.

Highlight stays frozen/pending: the model exposes it, but this first loaded-card
batch does not implement its source animation, scroll or clear lifecycle.
Chromium's post-touch-up sticky hover is also unmatched/pending, without an
approved platform exception. Other pending boundaries include official
ItemCard slot content, browser-native title tooltip, native metadata image
format coverage and actual device accessibility/contour acceptance. Fonts,
scoring thresholds and capture classification are unchanged.
