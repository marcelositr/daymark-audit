# Daily Task migration experiment

## Status

This document applies only to the isolated `feat/daily-task-migration` experiment in `daymark-audit`.

It does not authorize a merge into the frozen Daymark product baseline. The maintainer explicitly requested this work to be developed separately so the workflow can be evaluated before any decision about the main Daymark repository.

## Problem

The frozen product allows an open Task to be migrated to an existing Collection or scheduled to a Future Log month, but it does not allow an unresolved Task from Today or the current Monthly Task list to be deliberately carried into a Daily Log.

That omission creates unnecessary friction for the common Bullet Journal action of reviewing an unresolved Task and carrying it forward without retyping its content.

## Experimental behavior

For an open Task in **Today** or the current **Monthly Tasks** section, **Migrate** offers three deliberate destinations:

1. **Next day** — migrate to the Daily Log immediately following the current method date.
2. **Date** — migrate to an explicitly selected future Daily Log date.
3. **Collection** — preserve the existing migration-to-Collection behavior.

For Monthly Tasks, the Daily destination is anchored to the current method date, not to the first day of the Monthly Log.

**Schedule** remains separate and continues to target a Future Log month.

No unresolved Task is rolled forward automatically. The user must choose Migrate and choose the destination.

## Semantics

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

The existing schema already supports:

- Daily and Monthly ownership through `logs` and `entry_placements`;
- `migrated` Task state;
- source/destination lineage through `migrations`;
- fresh destination Entry identity.

The experiment therefore preserves schema v2 and existing encrypted persistence boundaries.

## Validation requirements

Before this experiment can be considered for the main Daymark repository, evidence must show:

- Today Task migration preserves source history and creates a distinct open Daily destination Task;
- Monthly Task migration preserves the Monthly source with `migrated` state and creates a distinct open Daily destination Task;
- content is preserved without retyping;
- migration lineage points to the destination Entry;
- lock/unlock preserves source, destination, state, and lineage;
- invalid or non-open sources do not create destination Daily Logs;
- Today and Monthly Tasks expose Next day, future date, and existing Collection destinations deliberately;
- historical Monthly remains read-only;
- existing Future scheduling and Collection migration behavior remains unchanged;
- formatter, analyzer, complete tests, Linux build, and Android build remain green on the exact candidate head.

## Decision boundary

This experiment intentionally contradicts the current frozen-product statement that additional migration destinations are not planned.

That contradiction is confined to this isolated audit branch. Merging or porting the behavior into the main Daymark product requires a separate explicit maintainer decision to revise the frozen product semantics and corresponding authoritative documentation.
