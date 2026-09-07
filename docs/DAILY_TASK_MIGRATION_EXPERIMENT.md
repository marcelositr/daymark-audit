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

Generic Task/Event/Note composers in **Today**, **Future**, and **Collections** accept the familiar Bullet Journal signifiers directly in the text field:

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

For an open Task in **Today** or the current **Monthly Tasks** section, **Migrate** offers three deliberate destinations:

1. **Next day** — migrate to the Daily Log immediately following the current method date.
2. **Date** — migrate to an explicitly selected future Daily Log date.
3. **Collection** — preserve the existing migration-to-Collection behavior.

For Monthly Tasks, the Daily destination is anchored to the current method date, not to the first day of the Monthly Log.

**Schedule** remains separate and continues to target a Future Log month.

No unresolved Task is rolled forward automatically. The user must choose Migrate and choose the destination.

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

The destination date must be later than the current method date in the experimental UI.

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
