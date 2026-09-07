# Bullet Journal decision-flow experiment

## Status

This document applies only to the isolated `feat/daily-task-migration` experiment in `daymark-audit`.

It does not authorize a merge into the frozen Daymark product baseline. The maintainer explicitly requested this work to be developed separately so the workflow can be evaluated before any decision about the main Daymark repository.

The experiment now evaluates three connected parts of the Bullet Journal method: fast capture through Rapid Logging, deliberate reflection, and explicit Task decisions including migration.

## Product loop under evaluation

The experimental loop is:

**Capture quickly → reflect → decide deliberately → continue**

The app must reduce mechanical retyping without removing the intentional decision that gives migration its value. No unresolved Task rolls forward automatically.

## Rapid Logging

Generic Task/Event/Note composers in **Today**, **Future**, and **Collections** accept the familiar Bullet Journal Bullets directly in the text field:

- `•` creates a Task;
- `○` creates an Event;
- `–` creates a Note;
- `-` followed by a space is accepted as a keyboard-friendly Note marker.

A recognized marker overrides the currently selected entry type and is removed before content is persisted. Plain text continues to use the selected entry type, so the existing controls remain fully usable.

Ambiguous ordinary text is not reinterpreted. For example, `-5 degrees` remains plain content instead of becoming a Note merely because it starts with a hyphen.

Monthly capture is intentionally not parsed this way because the Monthly Calendar and Monthly Tasks sections already define the entry type structurally.

## Deliberate reflection

**Today** keeps its existing reflection mode and the current **Monthly Tasks** section now follows the same deliberate-review pattern.

While reflecting:

- only open Tasks are shown;
- capture controls are hidden;
- non-decision actions such as Collection reference are hidden;
- each Task can be completed, migrated, scheduled, or discarded;
- after a Task is resolved it disappears from the active reflection list;
- an empty reflection state confirms that no open Tasks remain.

Monthly reflection is available only for the current writable month. Historical Monthly Logs remain read-only. Leaving Monthly Tasks, changing month, or rolling into a new month ends the reflection mode.

## Task migration

For an open Task in **Today**, **Migrate** offers three deliberate destinations:

1. **Next day** — migrate to the Daily Log immediately following the current method date.
2. **Date** — migrate to an explicitly selected future Daily Log date.
3. **Collection** — preserve the existing migration-to-Collection behavior.

For an open Task in the current **Monthly Tasks** section, the same choices are available plus **Next month**, which creates or reuses the next Monthly Log and places a fresh open Task in its Tasks section. The source remains in the current month with `>` state and lineage.

For Monthly Tasks, a Daily destination is anchored to the current method date, not to the first day of the Monthly Log.

**Schedule** remains separate and continues to target a Future Log month.

No unresolved Task is rolled forward automatically. The user must choose Migrate and choose the destination.

## Future arrival review

When a Future Log month becomes the current month, Daymark exposes a quiet review link only if that arrived Future bucket still contains open Tasks.

The arrived Future month is no longer treated as ordinary read-only history for those open Tasks. Each open Task can be deliberately:

- migrated into the matching current Monthly Tasks list;
- completed;
- discarded.

A Future Task migrated into Monthly keeps its Future source with `>` state, creates a fresh open Monthly Task, and records another lineage edge. If the Future Task originally came from scheduling, the journal therefore preserves the full chain: chronological source → Future destination → Monthly destination.

Future Events and Notes remain read-only in this experiment. Moving an Event into the Monthly Calendar would require an explicit day that the month-addressed Future entry does not contain, while Notes do not belong to either canonical Monthly section. The experiment does not invent those semantics.

## Migration semantics

Migration into a Daily Log uses the existing `migrated` movement kind and `>` source state.

The operation:

- requires an open Task;
- preserves the source Entry in its original Daily or Monthly Log;
- changes the source Task state to `migrated`;
- creates a fresh open Task in the destination Daily Log with the same content;
- records the existing migration lineage from source Entry ID to destination Entry ID;
- does not move an Entry in place;
- does not change the meaning of scheduling (`<`).

The destination date must be later than the current method date in the experimental UI. The session layer also rejects same-day or backward Daily-to-Daily migration, so the forward-only rule is not dependent on UI validation.

Monthly-to-Monthly migration must target a later Monthly Log. Future-to-Monthly arrival migration must target the Monthly Log for the same month as the Future source.

## Persistence impact

No database schema change is required.

The existing schema already supports Daily and Monthly ownership, Task states, migration lineage, and fresh destination Entry identity. Rapid Logging parsing and reflection are presentation/application behavior and do not alter encrypted persistence boundaries.

The experiment therefore preserves schema v2.

## Validation requirements

Before this experiment can be considered for the main Daymark repository, evidence must show:

- Rapid Logging recognizes Task, Event, and Note markers while preserving plain-text fallback behavior;
- recognized markers are stripped from persisted content;
- ambiguous text such as negative numbers is not accidentally reclassified;
- Today reflection continues to expose only unresolved Tasks for deliberate decisions;
- current Monthly Tasks can enter and leave reflection without affecting Calendar, Tracker, or historical Monthly views;
- Monthly Tasks can deliberately migrate into the next Monthly Tasks list while preserving source history and lineage;
- an arrived Future Task can deliberately migrate into the matching current Monthly Tasks list;
- a scheduled Task can preserve a two-edge lineage chain from original source through Future into Monthly;
- same-day and backward Daily-to-Daily migration is rejected before a destination is created;
- resolving a Monthly Task removes it from the active reflection list after refresh;
- Today Task migration preserves source history and creates a distinct open Daily destination Task;
- Monthly Task migration preserves the Monthly source with `migrated` state and creates a distinct open Daily destination Task;
- content is preserved without retyping;
- migration lineage points to the destination Entry;
- lock/unlock preserves source, destination, state, and lineage;
- invalid or non-open sources do not create destination Daily Logs;
- existing Future scheduling and Collection migration behavior remains unchanged;
- formatter, analyzer, complete tests, Linux build, and Android build remain green on the exact candidate head.

## Decision boundary

This experiment intentionally goes beyond the current frozen-product statement that additional migration destinations are not planned.

That divergence is confined to this isolated audit branch. Merging or porting the behavior into the main Daymark product requires a separate explicit maintainer decision to revise the frozen product semantics and corresponding authoritative documentation.

## Dated Monthly Calendar Tasks

The current Monthly Calendar may deliberately capture either an Event or a dated Task for a selected day. A dated Task remains a real Task with the normal Task lifecycle; the date belongs to its Monthly Calendar placement rather than becoming hidden Task metadata.

This does not turn Monthly into a general planner. The Calendar remains one row per day and accepts only method-native Events and Tasks.

## Future Event arrival

When a Future Log month arrives, an Event that has not already moved may be deliberately migrated into the matching Monthly Calendar. Because Future is month-addressed, the user must explicitly choose the calendar day during migration. No day is guessed automatically.

The source Future Event remains historical. The destination is a fresh Monthly Calendar Event with its own identity and migration lineage.

## Signifiers

Daymark exposes the three built-in optional Bullet Journal Signifiers already represented by the encrypted schema: `*` Priority, `!` Inspiration, and `◉` Explore. Signifiers remain optional context, never Entry types or Task states. Migration copies them to the fresh destination Entry while preserving them on the historical source. No custom Signifier UI is introduced.

## Final interaction polish

The experiment also validates a restrained digital interaction layer without
changing the Bullet Journal decision model:

- Collections are listed newest-first so recently-created structures remain
  immediately reachable while their internal entries keep chronological order.
- a just-created empty Collection can be undone for the same short window as an
  entry capture; the undo fails closed once the Collection has content,
  references, or Index membership;
- Signifiers keep a fixed visual column for zero through three marks, so the
  canonical Bullet column never shifts;
- Search can filter by Signifiers and accepts symbol-only shortcuts while
  leaving Signifiers optional visual metadata;
- password fields remain hidden by default but expose an explicit temporary
  visibility toggle in creation, unlock, restore, backup, and export flows;
- the compact More menu groups method navigation, data operations, and app
  settings in that order;
- visible action labels are shortened when the surrounding screen already
  supplies the noun, while tooltips and safety/error copy remain explicit.
