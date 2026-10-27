# Segmented tabs: reference and native evidence

The plugin manager and preset guide use the same source-generated segmented control. Its source behavior includes a named tab group, a single keyboard tab stop, arrow/Home/End selection, keyboard focus underline and 180 ms indicator/label motion with reduced-motion support. The guide is opened through its real preset-row entry point. Four guide-browser probes each use three independent contexts to verify initial focus after pointer, keyboard and keyboard-then-same-trigger-pointer activation; four manager probes are recorded separately.

The 64 cropped real-component comparisons cover both consumers, two sizes, two languages and two themes: 32 have matching dimensions, 0 reach the fixed 99.5% non-text target, and mean non-text agreement is 84.306%. The grouped results and every source/application pair are preserved in components/.

Sixteen pre-existing manager and neutral-shell captures are checked by raw RGBA bytes: 16/16 reference and 10/16 application images are unchanged. These preservation checks do not establish new visual acceptance.

Two native hardware GPU replays passed all recorded assertions; 22 Android scenes passed. The full thirteen-check preflight passed on the final tree, and all four normal/fixture artifacts have recorded hashes. Runtime source is declared explicitly and checked for unchanged product/fixture inputs. No raw process logs, local runtime URLs or credentials are copied.

The guide modal, panel layout and typography still differ from the source. Cropped control captures do not prove whole-page placement, and overall visual acceptance remains incomplete. receipt.json records provenance, native cleanup scope and remaining limits. No deployment or release.
