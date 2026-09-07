# Domain semantics

## Purpose

This document defines Daymark's frozen core Bullet Journal semantics independently of Flutter widgets, database tables, translated strings, or platform behavior.

The model remains deliberately small. Maintenance may correct implementation defects or add compatibility migrations, but it must not expand the domain with new product concepts while the product freeze is active.

## Entry types

Daymark has exactly three core entry types:

- `task` — an actionable item, rendered with `•` while open;
- `event` — a date-related occurrence, rendered with `○`;
- `note` — information, thought, observation, or fact, rendered with `–`.

Additional meaning must not be introduced by creating extra entry types such as `important`, `meeting`, `email`, `idea`, or `delegated`. Those concerns belong to content, the existing signifier/relationship model where applicable, or do not belong in Daymark.

Rendered symbols are presentation. Persistence and business logic use stable language-neutral semantic identifiers.

## Task lifecycle

Tasks have the following semantic states:

- `open` — not yet resolved;
- `completed` — intentionally completed, normally rendered as `×`;
- `migrated` — intentionally moved forward, normally rendered as `>`;
- `scheduled` — intentionally moved to the Future Log, normally rendered as `<`;
- `discarded` — intentionally judged no longer worth doing.

Discarding a Task is not the same operation as deleting data. A discarded Task remains part of the journal record. Permanent deletion is a separate destructive data operation and must never be represented as a Bullet Journal Task state.

Events and Notes do not inherit Task states for implementation convenience.

## Signifiers

Signifiers add context to an Entry without changing its Entry type.

The domain supports zero or more signifiers per Entry. The built-in semantic vocabulary may represent the conventional concepts already modeled by Daymark, including:

- `priority` (`*`);
- `inspiration` (`!`);
- `explore`.

Signifier identity remains separate from displayed symbol/localized label so persistence is stable and language-neutral. User-defined signifiers are not planned under the frozen product scope.

## Locations and chronological logs

Entries may belong to the supported method-native locations:

- Daily Log;
- Monthly Log;
- Future Log;
- Collection.

Index and Search are retrieval/navigation structures rather than owners of duplicated Entry content. A Search result is a transient view of an existing Entry and never changes that Entry's identity, owner, content, or Task state.

Reflection is method behavior and is not an `EntryType`.

### Daily Log

A Daily Log belongs to one method date.

Rapid Logging may capture Task, Event, or Note entries there. Advancing to a new day does not silently migrate unresolved entries.

Historical retrieval is non-creating: viewing a date with no persisted Daily Log returns absence rather than inventing an empty Log. A past Daily Log is read-only through the current product surface; retrieval does not grant capture, Task actions, migration, scheduling, references, completion, or discard.

Today remains the interactive current Daily Log. Historical navigation is retrieval over existing chronology, not a change of Entry ownership or an alternative calendar model.

### Monthly Log

A Monthly Log belongs to one month.

Its two canonical semantic sections are distinct:

- `calendar` — date-addressed Event placements within that month;
- `tasks` — monthly Task placements without a calendar date.

A Monthly Calendar date must belong to its owning month. A Monthly Task does not acquire a hidden day merely because a UI could display one.

Historical Monthly retrieval is read-only in the frozen product.

### Future Log

A Future Log bucket belongs to one month and is **month-addressed rather than day-addressed**.

Task, Event, and Note entries may be captured into that future month. A Future Log entry does not acquire a `monthly_section` or `monthly_calendar_date`.

The product shows a rolling six-month subset of future months, but visibility does not change ownership or delete older Future data.

Capturing a new entry directly in Future is different from scheduling an existing open Task into Future. Scheduling creates deliberate movement lineage.

## Trackers (optional Daymark adaptation)

A Tracker is a separate finite observation/commitment entity. It is **not** an `EntryType`, Task state, Log, Collection, placement, migration destination, or Index target. The core Bullet Journal ownership model remains unchanged.

A Tracker has a deliberate start date, planned end date, one stable visual slot, and an optional deliberate early-end date. Its effective data interval is inclusive from start through planned/early end. Outside that interval there is no Tracker datum.

Only explicit daily outcomes are persisted:

- `+1` means the user explicitly marked the commitment fulfilled;
- `-1` means the user explicitly marked it not fulfilled;
- absence of an explicit mark is rendered as `0` inside the active interval.

`0` is not a persisted outcome and must not be reinterpreted as failure. Removing a `+1` or `-1` mark returns the date to absence.

Ending a Tracker early preserves history through the chosen end date and removes marks after the new effective end. Daymark does not automatically renew a finished Tracker.

The combined graph and five fixed visual slots are frozen presentation/product constraints of the Daymark adaptation, not canonical Bullet Journal semantics. See `docs/TRACKERS.md`.

## Index

The Index is a deliberate ordered set of references to existing Logs and Collections.

An Index item targets a Log or Collection as a structure. It does not target an individual Entry.

Adding a structure to the Index:

- does not create or duplicate an Entry;
- does not change ownership;
- does not change Task state;
- does not create a new Log/Collection;
- does not happen automatically merely because a structure exists.

A given Log or Collection appears at most once. Index order records deliberate catalog order rather than timestamps, Search relevance, or chronological ownership.

Search is not Index. Search derives transient results; Index persists structures deliberately selected by the user.

Automatic indexing or Search-to-Index product behavior is not planned under the freeze.

## Search

Search is a transient read model over existing journal Entries. Matching an Entry does not create a new Entry, placement, Collection reference, migration edge, or Index item.

A Search result preserves source Entry identity, type, Task state when applicable, and actual owning context. Daily, Monthly, Future, and Collection ownership remain authoritative; Search never becomes an owner.

The frozen Search product behavior uses deliberate submitted text and case-insensitive literal substring matching over Entry content, with read-only source-aware results and real source navigation.

Search does not add query history, ranking, filtering, Collection-title search, a persistent/full-text side index, or other new retrieval capabilities under the current product freeze.

## Migration and scheduling

Movement is always deliberate.

Daymark never silently migrates unresolved items because a date changed or because software can automate the action.

Movement records lineage rather than overwriting history. The model preserves:

- source Entry identity;
- destination Entry identity;
- source location;
- destination location;
- movement kind;
- timestamp.

For an open Task:

- `>` means deliberate forward migration to the supported non-Future destination;
- `<` means deliberate scheduling into Future.

Only an open Task can change to migrated/scheduled state. Completed, discarded, migrated, or scheduled Tasks cannot be moved again as though still open.

The frozen product exposes:

- scheduling from Today/Daily and Monthly Tasks into one selected Future month;
- forward migration from Today/Daily and Monthly Tasks into one explicitly selected existing Collection.

No additional movement sources/destinations are planned under the freeze.

Scheduling preserves the historical source in its original owner with `scheduled` state and creates a new open Task in the chosen Future bucket with lineage.

Migration to Collection preserves the historical source with `migrated` state and creates a new open Task owned by the selected existing Collection. Migration never silently creates or chooses the destination.

Movement normally creates a destination Entry while retaining source history. The destination Task begins open; the source retains the terminal state recording the decision.

A Future destination always uses scheduling semantics. Forward migration in the frozen product targets an existing Collection. The current Monthly Log is not a shortcut migration destination for a Today Task.

One source Entry may have at most one direct outgoing movement. UI must not offer contradictory second movement after outgoing lineage exists.

## Collection references versus migration

Daymark distinguishes:

1. **Reference/link** — an Entry remains in its original chronological location and is also discoverable from a Collection. Task state does not change.
2. **Migration to Collection** — the user deliberately moves an open Task; movement lineage is recorded and the source Task becomes `migrated`.

A Collection reference keeps the same Entry identity, owner, content, and Task state. The Collection presents it separately as read-only content rather than granting ownership-level Task actions.

Removing a reference deletes only the reference relationship, never the source Entry.

Additional reference/Collection ownership capabilities are not planned under the freeze.

## Immediate capture undo

Immediate capture Undo is a narrow correction operation for an accidental fresh capture. It is not `discarded`, an Entry type, a Task state, or a generic historical delete path.

Undo may destroy only an Entry that is still pristine after capture. If the Entry has been semantically changed or participates in movement, Collection references, signifiers, or other journal relationships, Undo fails rather than rewriting history.

## Identity and history

Every persisted Entry has a stable identifier independent of text, date, symbol, language, or screen position.

Editing/correction behavior must not silently change semantic identity. Movement history and relationships refer to stable IDs rather than copied display text.

An Entry is not moved between owners in place to simulate movement. Historical source placement remains part of the journal record and the destination receives its own identity.

Database schema may change only for concrete maintenance/compatibility/security reasons. Such changes must preserve these frozen semantics through explicit migrations and compatibility tests.

## Experimental Bullet Journal fidelity extensions

On the isolated `feat/daily-task-migration` branch, the maintainer has explicitly approved evaluation of additional method-native semantics beyond the frozen baseline:

- Monthly Calendar may own dated Task entries as well as Events;
- an arrived Future Event may migrate deliberately into the matching Monthly Calendar after the user chooses a day;
- built-in Signifiers (`priority`, `inspiration`, `explore`) are user-visible optional Entry context;
- Signifiers follow a migrated Entry to its fresh destination while remaining attached to the historical source;
- an Event with outgoing migration lineage is considered resolved for Future arrival review even though Events do not acquire Task state.

These rules remain experimental until this PR is explicitly promoted into the main Daymark product.

### Immediate correction window

Immediate Undo is a correction affordance, not historical editing. A newly
created Collection may be removed only while it is still untouched and has no
entries, references, or Index membership. Once it participates in journal
structure, deletion through that short-lived Undo is rejected.

Signifiers remain optional metadata on an Entry. Search may use that metadata
as a read-only filter, including combinations of multiple Signifiers, without
changing ownership, state, migration, or the canonical Bullet grammar.
