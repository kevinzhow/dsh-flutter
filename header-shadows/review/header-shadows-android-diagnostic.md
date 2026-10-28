# Android model-trigger failure: diagnosis and canonical fix

The retained failure is caused by the model trigger's accessibility semantics
merging into its new scene-wide Focus ancestor. The recorded physical tap hits
blank content instead of the painted trigger. This is a missing canonical
control boundary exposed by the fixture's CallbackShortcuts wrapper; it is not
evidence that model selection or the new Header focus state failed to activate
after an on-target tap.

## Exact retained run

- Runtime head: `2293a830c1edecc18d5e488e67493fd2e90f2d10`.
- Runtime tree: `25db72d02c40e38e459c6daf4e11265ffbb7488e`.
- Fixture APK SHA-256:
  `c0e1b1b0153274f08359ef9318bba825afc9212c7aa86603f6a935b89965c903`.
- Retained output: `build/native-header-shadows-android/` in
  `scratch/whalee-source-shadows`.
- Failure: `Visible: Effort`, after the model trigger input.

The last recorded input targets `DeepSeek V4.1 Flash` at **(540,1236)**, using
the supposed button bounds **[0,136][1080,2337]**. The actual UIA node is already
clickable and has this combined label:

```text
Select model, current DeepSeek V4.1 Flash, reasoning effort Max
Selection: none
Sidebar action: new-session
```

The driver's `click` method at `scripts/header-shadows-android.py:108–145`
therefore does not need to climb to a clickable ancestor for this input. Its
substring match finds the already merged button; `len(candidates()) == 1`
accepts it and the driver taps that huge rectangle's center. Uniqueness does not
establish that the node is the actual control's touch rectangle.

The retained successful predecessor at
`scratch/whalee-reported-families/build/native-reported-android-final5/model-closed.xml`
has separate status/result nodes and an isolated model trigger at
**[667,2201][1017,2274]**, labelled only with model and effort. The current
selected rectangle is about 93 times its area. The recorded (540,1236) point
is outside that isolated trigger rectangle. The current screenshot visibly
places the trigger at the bottom right while the recorded tap is in blank
middle content.

Current `model-closed.xml` and `failed-8.xml` are byte-identical, showing that
the merge already exists before the attempted click; it is not an aftermath
of opening and dismissing a menu. Both PNGs show the closed state. Their bytes
differ, so PNG equality is not claimed.

## Source trace

The new native fixture wraps its entire scene Stack in CallbackShortcuts at
`reported_families_main.dart:86–125`, with an F6 binding for the Header scene.
Pinned Flutter 3.47.6's `shortcuts.dart:1221–1234` implements CallbackShortcuts
with a Focus widget. Focus defaults `includeSemantics` to true and emits a
Semantics annotation over its entire child at `focus_scope.dart:714–732`.

The actual model trigger's Semantics at `model_select.dart:100–105` had
`button`, `enabled`, `label`, `excludeSemantics` and `onTap`, but no
`container: true`. Excluding descendants does not establish the control's own
semantic boundary. Its action/label can still merge upward along with unrelated
sibling labels. The shared DshButton already establishes its own boundary with
`container: true` at `dsh_button.dart:510–515`.

ModelSeat and its testing fixture are byte-identical between the successful
37fbe33 runtime and 2293. ModelSeat uses its own FocusableActionDetector and
GestureDetector, not the new Header DshButton profile. `_toggle` at
`model_select.dart:43–50` still requests trigger focus and toggles the panel.
The new shared `pointerOwnsOutline` field changes Header outline presentation;
it does not change ModelSeat's gesture callback or hit-test bounds. The recorded
input provides no basis for changing menu timing, callbacks or focus dismissal.

## Authorized minimal fix and RED/GREEN proof

Root authorized a canonical accessibility correction after the read-only
diagnosis. The product diff adds only **`container: true`** to ModelSeat's
existing Semantics. The fixture's Focus wrapper remains intact. There is no
style, layout, onTap, directory, panel, shortcut or shared-focus-field change.

Two regression tests were added to the existing model feature test file. They
mount the real trigger under Focus and under CallbackShortcuts, with unrelated
selection/sidebar-status text. They compare the full native semantics rectangle,
transformed through its semantic ancestry, to the actual rendered trigger rect;
require its exact isolated label and tap action; then tap the native rectangle's
center and require the real model menu and effort entry to appear.

Before the product change, **both tests fail**:

```text
Expected trigger: Rect.fromLTRB(210.3, 748.0, 366.0, 776.0)
Actual semantics: Rect.fromLTRB(0.0, 0.0, 390.0, 800.0)
```

After adding the boundary, both tests pass, including the actual pointer tap
and menu-opening assertions. This reproduces and resolves the recorded failure
mechanism without choosing guessed device coordinates or retrying the failed
input. RED/GREEN logs:

- `.local/model-trigger-semantics-red.log`.
- `.local/model-trigger-semantics-green.log`.
- `.local/model-trigger-semantics-full.log` for the existing model suite.

Final validation after removing a redundant test import:

- `.local/model-trigger-semantics-full-final.log`: **37/37 pass**, including
  both new bounds regressions and the existing locked/accessibility, pointer,
  keyboard, selection and menu tests.
- `.local/model-trigger-semantics-analyze-final.log`: **No issues found** for
  the two changed files.
- The final diff is one product line plus 75 test lines; `git diff --check`
  passes. Both paths remain unstaged on the 2293 baseline for root's commit.

| Final handoff input | SHA-256 |
| --- | --- |
| `model_select.dart` | `2e9a1aa955130ac486b0014901b44d33bbd78722f2ae890a0288a9ba5b85e68d` |
| `model_selection_test.dart` | `80145a244f7ebc21f560ae575e3650131c7b5e759c80bee4f6d17af3295fde00` |
| Full final test log | `c5277fc8086cbb337e4d933304c15b96b0da2f360480fa45fae54fc30ce472e1` |
| Final analysis log | `b2348d3aaf1a7b6a0678e58dc055a40522c8e9cbee47c8d1f05cda74d2c9a33b` |

No ADB, emulator, native process or GPU replay was run by this diagnosis/fix.
Root owns the new clean candidate, rebuilt APK and complete native replay.
The earlier failed receipt stays a failure; the new widget proof does not
retroactively convert it into an Android pass.

## Retained failure fingerprints

| Input | SHA-256 |
| --- | --- |
| `receipt.json` | `3208d8e60257963e4591718daaba64cc3913df55fed8d93a88d1b07b2c8f6025` |
| `model-closed.xml` / `failed-8.xml` | `b4a340cab349e5af50601308c2f48a82e4e01c42063187dbb9668ad42fef38dc` |
| `failed-8.png` | `a104c47b3fb35929f50e1d5a759b5e5d4f121ddc5a6f80803dccf8fd41668d8e` |
| Original `model_select.dart` at2293 | `16430a9d9ff5487915d55073c9c7a5ddb9c9cef5462a0f2a805e6951fc4ac397` |
| Unchanged `testing.dart` | `a9cc6b3e0b23c4cc54e973928e971822ac8336734c19c37a5478b1c4f24b7bf0` |

Only the two explicitly assigned feature source/test paths and this diagnostic
note were edited. Both code paths are left unstaged for root's coordinated
commit; the separate root-owned theme metadata is preserved.
