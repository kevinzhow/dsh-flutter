# Agents, skills and automation tasks

The feature lives in `features/dsh_feature_agent_management`. Its Host contracts,
locales and behavior references use the repository's pinned DSH source.

- Presets: settings/default selection, read-only composition and guides, one-shot
  selection for a blank Session, and Creator landing in a new explicit `cordis`
  Session. A running Session's composition remains immutable.
- Skills: Session-keyed catalog, shared warmup, invalidation, literal `/name `
  insertion, confirmed original-text references and durable tool-result rows.
  Editable references retain their full text and cursor offsets. Preview taps
  resolve glyph bounds and open the original Session's file.
- Goals: the dock reads durable Session projections. Live activation reads cannot
  overwrite newer events or projections. Edits, pause/resume and clearing carry
  the current projected identity/revision; a replacement invalidates an old editor.
- Background jobs: reference-counted roster/output streams, generation fences,
  byte-cursor continuation and a bounded rendered tail. Output follows only while
  expanded. Stopping requires two presses and waits for roster convergence.
- Automation tasks: a searchable cross-Session manager, active/inactive filters,
  exact expected-record updates, concurrent draft preservation, elapsed interval
  units, structured/raw Cron editing, explicit zones, retained history and
  confirmed deletion. Session header/sidebar entries and replayed creation cards
  preserve the original binding. Only paired, successful root creations produce
  a card; a settlement after the final assistant text still belongs to its Turn.

Android obtains its device IANA zone from the native runtime. Linux checks the
native zone sources. An unknown zone identity falls back explicitly to UTC;
conversion and business validation remain the Host's responsibility. Original
Session navigation rechecks current availability and archive state.

## Validation entry points

- `tool/vectors/gen_agents_tasks_expected.py --check packages/dsh_models/test/fixtures/agents_tasks.json`
  invokes the actual pinned TypeScript Cron parser/builder, timing helpers,
  TaskDetail draft merge, creation-card decoder and Skill matcher. `tool/preflight`
  runs this check and all model/feature/application tests.
- Application regressions: `apps/dsh_flutter/test/agents_tasks_flow_test.dart` and
  `skill_draft_flow_test.dart` exercise Creator routing and live literal editing.
- `apps/dsh_flutter/test/parity/agents_tasks_main.dart` is a synthetic native replay
  target. It uses generated Remote clients and projected updates, with no real
  account, secret or private conversation. The production application uses the
  separate normal `lib/main.dart` target.
- `tool/parity-desktop/agents-tasks-cases.json` drives Weston GPU interactions.
  `tool/parity-ext/build-agents-tasks.py` compares five actual upstream component
  families in English/Chinese, light/dark, and desktop/phone dimensions.

## Remaining alignment work

Functional validation does not assert pixel parity. Precise card/field typography,
spacing, color and hover behavior remain in the visual-alignment task. Date/time
rows currently accept explicit values; the zone picker exposes searchable IANA
identities rather than ICU city labels. Editable Skill references preserve literal
text rather than using an atomic chip. Tool inspection needs the separate
inspection/preview owner.

Sidebar task bindings are in-memory navigation parameters. Durable sidebar layout
and binding restoration belong to the platform/recovery work; this change does not
claim restored-tab recovery. Synthetic native actions and production-root routing
are recorded separately in the validation evidence.
