# Build plan

The sequencing rule is: **prove that people value the artwork, then prove that smart retrieval makes creation materially easier.** Estimates assume a small experienced iOS/product team and will be revised after measured spikes.

## Phase 0 — Product and repository foundation

- Establish product brief, architecture, test strategy, contribution rules, and decision log.
- Interview 12–15 pet owners with large libraries; run concierge mosaic tests.
- Assemble ten licensed/consented golden hero-and-source projects.
- Agree a two-distance visual-quality rubric and meaningful-creation definition.

**Gate G0:** evidence supports the problem, artwork outcome, access tolerance, and a viable MVP; otherwise revise or stop.

## Phase 1 — Technical spikes (weeks 1–2)

**Status:** Deferred by product decision on 2026-09-12 because the current environment is Windows-only. Gate G1 remains open; see `decisions/001-phase-1-deferral.md`.

- Benchmark PhotosPicker/PhotoKit import, thumbnail throughput, iCloud states, memory, heat, and cancellation on physical devices.
- Port the prototype engine behind Swift protocols and create deterministic golden tests.
- Benchmark preview and high-resolution strip rendering.
- Record ADR-001 (deployment/device floor) and ADR-002 (permission strategy) from measurements.

**Gate G1:** a recognisable preview meets the agreed p50/p90 target on the device floor without unacceptable memory or heat.

## Phase 2 — App skeleton and persistence (weeks 2–4)

**Status:** Complete for the provisional iOS 17 simulator floor. See `gates/g2-app-skeleton.md` for evidence and remaining risk.

- Create the universal SwiftUI Xcode project and module boundaries described in `ios/README.md`.
- Implement navigation, design tokens, local project recipes, migrations, dependency injection, CI, linting, and privacy-safe analytics allowlisting.
- Add accessibility foundations and representative iPhone/iPad layouts.

**Gate G2: Passed 2026-09-13.** The empty walking skeleton runs on iPhone and iPad Simulators and project state survives relaunch.

## Phase 3 — Hero and manual sources (weeks 4–6)

**Status:** In progress. Native selected-photo presentation, atomic private caching, bounded import progress with cooperative cancellation, thumbnail review, source sufficiency, and lifecycle cleanup for replaced heroes, rejected or cancelled source batches, and persisted source removal are implemented. Interactive picker, crop, format, iCloud-specific progress, and missing-asset validation remain pending.

- Implement hero selection/crop and manual multi-selection without broad library permission.
- Review, add/remove, and validate source sufficiency; handle orientation, formats, iCloud progress, cancellation, and missing assets.

**Gate G3:** a tester can reliably reach a confirmed source set without an account or full-library permission.

## Phase 4 — Preview engine (weeks 6–8)

- Implement versioned descriptors, candidate scoring, repeat penalties, deterministic assignment, progress, cancellation, and preview caching.
- Validate ten golden projects for likeness, tile authenticity, diversity, and crop safety.

**Gate G4:** at least 8/10 golden projects pass the quality rubric and interrupted jobs recover safely.

## Phase 5 — Complete the editing loop (weeks 8–11)

- Add zoom, tile inspection, source detail, likeness/authenticity control, replace/pin, undo, and persistent edits.
- Run moderated usability tests and accessibility checks.

**Gate G5:** new users can improve a tile and understand the main control without photomosaic terminology.

## Phase 6 — Export (weeks 11–13)

- Implement JPEG/PNG policies, strip-based rendering, disk preflight, cancellation/recovery, save/share, colour profile, and physical-size guidance.
- Produce and inspect at least one reference print.

**Gate G6:** ten diverse exports reopen correctly, match preview assignment, and one physical print passes the rubric.

## Phase 7 — Smart Library experiment (weeks 10–14, feature flagged)

- Add contextual permission education and all PhotoKit authorisation states.
- Implement deterministic `MemoryQuery` parsing, editable chips, SQLite index, bounded Vision analysis, checkpointing, change observation, ranking, review, and index deletion.
- Benchmark 1k/10k/50k libraries and measure precision, energy, heat, storage, and time saved.

**Gate G7:** ship enabled or labelled beta only if retrieval saves real effort at an agreed precision and device cost. Failure does not block manual-selection release.

## Phase 8 — Hardening and launch (weeks 14–20)

- Complete data inventory, threat model, file protection, package/privacy-manifest audit, state matrix, accessibility audit, and schema/recipe migration tests.
- Run internal then 30–50-person external TestFlight, measure the full funnel, interview completers/abandoners, resolve all P0/P1 issues, and prepare the App Store submission and phased-release controls.

**Gate G8:** privacy claims match behaviour, no open P0/P1 defects remain, release metrics are acceptable, and rollback/support ownership is explicit.

## Required test matrix

Cover photo access (selected/limited/full/denied/revoked), availability (local/iCloud/missing), source sizes (insufficient/100/500/1,000/over-limit), interruptions (cancel/background/terminate/low memory/storage/network), iPhone/iPad layouts and accessibility, plus every export path.

## Immediate next actions

1. Confirm team shape, budget band, and target release window.
2. Recruit interview participants and define the concierge test.
3. Build ten consented golden projects and the quality rubric.
4. Obtain temporary or hosted macOS access to validate the package and create the SwiftUI application target.
5. Run the deferred physical-device spikes before making performance-sensitive commitments.
