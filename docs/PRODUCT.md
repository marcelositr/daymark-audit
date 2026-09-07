# Product principles

## Purpose

Daymark exists to provide a faithful digital implementation of the Bullet Journal method without turning personal organization into a productivity platform.

The application helps the user capture, reflect, migrate, discard, and retrieve information with as little interface friction and distraction as possible.

## Product scope status

**Daymark's functional product scope is frozen.**

The maintainer declared the current product shape feature-complete on 2026-09-05. The application is intended to remain this product rather than grow through a continuing feature roadmap.

Normal development is maintenance only:

- bug and regression fixes;
- security fixes and necessary hardening;
- compatibility and data-migration fixes;
- Linux/Android platform, dependency, toolchain, build, packaging, signing, and CI maintenance required to preserve supported behavior;
- accessibility, localization, documentation, and internal corrections that preserve existing product semantics.

The freeze does not prevent prerelease/beta/RC/stable progression. Release stages measure validation and stability, not feature expansion.

A change that introduces a new user capability, new workflow concept, new supported platform/language, or new convenience layer is outside the frozen scope unless the maintainer explicitly reverses this decision first.

## No feature roadmap

The following are intentionally **not planned** and must not be treated as merely deferred work:

- device-assisted or biometric unlock;
- recovery-secret UX, account recovery, or maintainer reset/backdoors;
- cloud sync, accounts, remote services, collaboration, or social features;
- AI-generated or AI-assisted journal content inside Daymark;
- Windows, macOS, iOS, web, or other additional product targets;
- additional product languages beyond English, Portuguese (Brazil), and Spanish;
- explicit language-selection UI;
- new migration destinations or automatic rollover/migration behavior;
- editing historical Daily/Monthly logs;
- Collection-owned-entry referencing, richer Collection models, arbitrary properties, Kanban, workspaces, or databases;
- richer Search/filtering/full-text ranking/indexing as a product feature;
- new Index automation or Search-to-Index actions;
- additional reflection engines or planner/calendar abstractions;
- automatic backup schedules/retention systems;
- attachments;
- dashboards, feeds, streaks, badges, XP, productivity scores, engagement loops, or gamification;
- freeform page/canvas/drawing/layout editing.

Historical documentation may mention some of these as "future", "later", or "deferred" because it records earlier design stages. Those phrases are historical context only and do not represent an active roadmap.

## Digital minimalism

Daymark deliberately avoids features whose primary purpose is to increase engagement with the application.

The product must not introduce:

- advertising;
- feeds;
- streaks, badges, XP, or gamification;
- productivity scores;
- attention-seeking notifications;
- unsolicited suggestions;
- dashboards for the sake of dashboards;
- social or collaborative features;
- AI-generated journal content;
- automatic decisions that replace intentional reflection.

Animations must be restrained and functional. Colors, typography, navigation, and persistent controls remain minimal.

## Method fidelity

The core vocabulary is intentionally small:

- Task;
- Event;
- Note;
- Daily Log;
- Monthly Log;
- Future Log;
- Collection;
- Index;
- Migration;
- Reflection.

Migration is a deliberate decision. Unresolved entries are never silently rolled forward merely because software can automate it.

The detailed domain semantics are defined in `docs/DOMAIN.md`.

## Frozen chronological product shape

The digital implementation keeps method-native chronological surfaces distinct instead of merging them into a general planner.

### Daily Log / Today

Today represents the current Daily Log and supports Rapid Logging of Task, Event, and Note entries.

The date changes automatically at the method-day boundary, but unresolved entries are not automatically migrated because the calendar advanced.

Earlier Daily Logs may be opened through a dedicated **read-only historical route**. Historical Daily browsing does not create a missing Daily Log merely because the user views that date and does not expose capture, Task actions, migration, scheduling, references, completion, or discard.

A historical day that never existed appears empty without becoming persisted state or an Index candidate. Historical navigation may move between earlier dates but does not advance into Today as though the current Daily Log were historical. Returning to Today restores the interactive Rapid Logging surface.

Active Daymark Trackers may appear in Today as a compact `+ / -` marking surface. A Tracker is not a Daily Entry and does not create a Task per day. It is the documented optional Daymark adaptation defined in `docs/TRACKERS.md`.

This history surface is retrieval, not a generic calendar workspace.

### Daily Reflection

Daily Reflection is contextual inside Today rather than a separate permanent workspace.

It isolates unresolved Tasks and requires a deliberate decision among the actions already supported by Daymark: Complete, Migrate, Schedule, or Discard.

Reflection never performs automatic rollover, scoring, prioritization, recommendation, or engagement prompting.

### Monthly Log

Monthly preserves the method's two canonical areas:

- **Calendar**: one row per date, with dated Event entries;
- **Tasks**: a monthly Task list.

Daymark additionally hosts the optional **Tracker** section. Tracker is a Daymark-specific adaptation for finite daily commitments and reflection; it is not a third canonical Monthly Log entry-placement type and is not presented as an official Ryder Carroll rule.

The **current month** remains interactive and supports capture plus deliberate Task actions. The Tracker view may create, mark, and deliberately end Trackers.

Earlier Monthly Logs are **read-only historical retrieval**. Historical browsing does not create a missing Monthly Log, expose capture/Task actions, or move forward past the current month.

Historical Monthly editing and richer Monthly reflection are not part of the frozen product scope.

### Future Log

Future Log is a rolling overview of **six future months**, beginning with the month immediately after the current month.

Each month is a month-addressed bucket. Future does not assign entries to a day inside that month and does not become a second day-level calendar.

Rapid Logging may place Task, Event, and Note entries into the selected future month. Scheduling an existing open Task into Future is a separate deliberate movement action, not the same as capturing a new Future entry.

When the current month advances, the visible Future horizon rolls forward. Existing historical data remains persisted in its original month bucket even when that bucket falls outside the six-month overview.

### Collections

Collections are deliberate topic/project-oriented journal containers, not generic configurable workspaces.

The Collection surface supports:

- listing and creating Collections;
- opening one Collection;
- Rapid Logging Task, Event, and Note entries owned by that Collection;
- completing or discarding open Tasks inside that Collection;
- receiving deliberately migrated open Tasks from Today or Monthly Tasks;
- displaying deliberate references to Today, Monthly, and Future entries in a separate read-only section;
- removing a Collection reference without deleting or mutating its source Entry.

A **Collection reference** does not move or copy the source entry. The source remains owned by its original Daily, Monthly, or Future Log with the same stable Entry identity and Task state. The Collection displays that entry as a reference only, and Task actions are not exposed through the reference.

Daymark does not auto-select or create a Collection as a side effect.

Additional Collection abstractions are outside the frozen scope.

### Index

The Index is a deliberate Bullet Journal catalog of existing journal structures. It is persisted independently from Search and never duplicates Entry content.

The Index supports:

- listing indexed Logs and Collections in deliberate order;
- adding an existing Daily, Monthly, or Future Log;
- adding an existing Collection;
- excluding a structure once already indexed;
- deliberately reordering or removing Index items;
- opening an indexed structure through its real product route.

Adding something to the Index does not move it, copy it, change Entry ownership, alter Task state, or create a new Log/Collection. Daymark never auto-indexes every structure.

Search remains a separate retrieval mechanism. Search-to-Index automation is outside the frozen scope.

### Search

Search is explicit local retrieval over existing Entry content. It is not another owner, Collection, or persistent catalog.

Search:

- runs only after the user deliberately submits text;
- performs case-insensitive literal substring matching over existing Entry content;
- shows the result's real Entry type/Task state and owning Daily, Monthly, Future, or Collection context;
- remains read-only and exposes no Task, migration, scheduling, reference, or ownership actions;
- presents quiet prompt/empty states;
- refreshes the last submitted query when the retained Search section becomes active again;
- opens a result through the real route of its owner.

Search does not create Entries, Collection references, Index items, query history, an external plaintext index, ranking, or filtering systems.

### Migration and scheduling

Migration and scheduling use real method-native destinations.

**Scheduling (`<`)** is available for open Tasks in Today and Monthly. The user deliberately chooses one of the visible Future months. The historical source stays in place with scheduled state, and the selected Future month receives a fresh open Task with lineage back to the source.

**Forward migration (`>`)** is available for open Tasks in Today and Monthly Tasks into an existing Collection. The user deliberately chooses the destination Collection. The historical source stays in place with migrated state, and the chosen Collection receives a fresh open Task with lineage.

A Future destination always uses scheduling semantics. Forward migration uses the existing Collection destination defined by the product.

Daymark does not treat the current Monthly Log as a shortcut destination for a Today Task. Migration from Future, migration from Collection-owned entries, or additional destination models are outside the frozen scope.

Cross-surface movement/reference must be immediately visible when the destination section is reactivated. Retained navigation state is not permission to show stale data.

## Immediate capture correction

A successful capture in Today, Monthly, Future, or a Collection may expose a short-lived **Undo** action as mechanical error correction.

Undo is not a general Edit/Delete feature and is not a Bullet Journal task state. It may reverse only the freshly captured Entry while that Entry is untouched and has no migration, Collection reference, signifier, or other journal relationship.

Once the Entry participates in journal history, normal method actions are authoritative.

## Transient feedback

Daymark uses one quiet in-layout notice channel for transient operational feedback. Notices never cover Rapid Logging fields, navigation controls, or journal content the user is actively manipulating.

The channel has three restrained behaviors:

- **Undo**: five seconds, with one explicit action;
- **Info**: approximately three seconds;
- **Error**: approximately six seconds, non-modal unless a separate user decision is required.

Notices do not steal keyboard focus, queue into an attention feed, persist as engagement prompts, or create notification history.

## Trackers

Trackers are an optional finite Daymark adaptation already included in the frozen product.

They:

- store explicit daily `+1` or `-1` marks;
- interpret absence as `0` only inside the effective Tracker period;
- are separate from Task/Event/Note Entry ownership;
- have a finite planned period and may be deliberately ended early;
- are limited to the existing five visual slots/colors;
- appear read-only in historical Monthly views;
- may expose compact current-day controls in Today;
- use the existing restrained reflection graph and no scores/streaks/gamification.

Exact provenance and constraints are documented in `docs/TRACKERS.md`.

## Local-first

The journal belongs to the user.

Daymark works without an account or network connection. Core functionality does not depend on a remote service.

User data is exportable through the documented encrypted Backup/Restore and explicit plaintext Open Export boundaries.

No network product feature is planned under the frozen scope.

## Supported platforms

The supported product targets are:

- Linux;
- Android.

The architecture keeps domain/application logic reasonably platform-independent for maintainability, but additional product platforms are not planned while the scope freeze is active.

## Languages and localization

The supported product languages are:

- English;
- Portuguese (Brazil);
- Spanish.

English is the canonical source/fallback locale.

On first run, Daymark follows the operating-system locale only when it matches a supported product locale. Exact Brazilian Portuguese selects `pt_BR`; any Spanish regional locale selects general Spanish `es`; English selects English; unsupported locales fall back to English.

The Flutter localization generator requires a parent `pt` resource when `pt_BR` exists. That parent is a technical fallback and does not expand the supported-language promise.

Product behavior, domain rules, persistence values, and identifiers never depend on translated display strings.

The maintainer explicitly approved Spanish as the sole language-scope expansion on 2026-09-06. Additional language support beyond English, Portuguese (Brazil), and Spanish, plus explicit language-selection UI, remain outside the frozen scope.

## Navigation

The journal navigation model contains:

- Today;
- Monthly;
- Future;
- Collections;
- Search;
- Index.

Wider desktop layouts expose all six directly in the navigation rail. Compact/mobile layouts keep Today, Monthly, Future, and Collections as direct bottom destinations and use a minimal **More** destination for Search and Index.

Historical Daily navigation is contextual under Today rather than a seventh top-level destination.

Reflection remains contextual rather than a permanent top-level workspace.

Settings/support controls such as Backup, Open Export, Appearance, and About remain secondary and do not compete with journal navigation.

## Visual direction

Daymark supports Light, Dark, and System-following appearance.

The shared visual metaphor is a minimal notebook/sketchbook page:

- comfortable page-like spacing;
- strong emphasis on journal content;
- minimal chrome;
- restrained controls and feedback;
- light/dark palettes as equivalent reading surfaces.

The notebook metaphor is visual, not structural. Daymark is not a freeform canvas, drawing application, page designer, or drag-and-drop layout system.

Linux and Android feel like the same journal while using layouts appropriate to each form factor.

## Maintenance test

Before accepting any post-freeze change, ask:

1. Is it fixing a reproducible defect, vulnerability, compatibility failure, platform/toolchain breakage, packaging/release problem, accessibility regression, localization defect, or documentation error?
2. Does it preserve the existing method/product semantics instead of adding a new user capability?
3. Does it avoid creating a new product concept, workflow, setting, supported platform/language, or convenience layer?
4. Is the smallest safe correction sufficient?
5. Are existing data/security compatibility boundaries preserved and tested where relevant?

If the answer to the first question is no, or the change expands what Daymark does, it does not belong under the current product freeze without an explicit maintainer decision to reopen scope.

## Experimental Bullet Journal fidelity extensions

The isolated `feat/daily-task-migration` branch additionally evaluates three method-native capabilities explicitly approved by the maintainer:

- dated Tasks in the Monthly Calendar, alongside Events;
- deliberate Future Event arrival migration into a user-selected day of the matching Monthly Calendar;
- optional built-in Signifiers for Priority, Inspiration, and Explore.

These additions preserve Daymark's minimalism: there is no automatic rollover, no guessed Event date, no new planner abstraction, and no custom Signifier system. They remain experimental until the maintainer explicitly promotes this PR.

### Interaction polish principles

- reserve a stable visual column for zero to three Signifiers before the Bullet;
- keep recently-created Collections easiest to reach;
- offer short-lived Undo for accidental capture or empty Collection creation,
  not permanent destructive editing;
- let Search exploit structured Signifiers without making them mandatory;
- keep password visibility temporary and opt-in on every password surface;
- prefer context-aware action verbs when the screen already names the object;
- keep the primary navigation ordered Today → Monthly → Future → Collections,
  with Index before Search inside the secondary menu.
