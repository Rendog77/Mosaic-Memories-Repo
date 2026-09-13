# Gate G2 — App skeleton and persistence

**Decision:** Passed on 2026-09-13 for the provisional iOS 17 simulator floor.

## Evidence

- The universal SwiftUI application and all local package modules compile for a generic iOS Simulator in GitHub Actions.
- CI installs and launches the application on available iPhone and iPad Simulators.
- Both device classes complete a cold launch, termination, and process relaunch.
- Each simulator receives a versioned project recipe in the production Application Support location.
- The running application uses `JSONProjectStore` to decode that recipe successfully before and after relaunch.
- Unit tests cover save/load/delete, catalogue recovery, schema migration, and exact date preservation.

## Scope and remaining risk

This gate establishes the empty walking skeleton and recipe persistence contract. It does not close deferred Gate G1, prove physical-device performance, exercise the system photo-picker UI interactively, or certify final iPhone/iPad layouts. Those items remain explicit Phase 1, Phase 3, and hardening work.
