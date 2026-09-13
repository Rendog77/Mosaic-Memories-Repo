# Native iOS/iPadOS app

This folder contains the platform-independent production foundation as a Swift Package. Do not hand-author an `.xcodeproj` on Windows: create and validate the application target with the installed Xcode version on macOS.

## What is available now

- Versioned, Codable project recipes and asset references.
- Protocol boundary for the mosaic engine.
- Atomic JSON project persistence behind an actor and protocol.
- Typed, allowlisted analytics events that cannot accept arbitrary fields.
- The manual creation workflow state and source-count validation.
- XCTest coverage and a macOS GitHub Actions workflow.
- A SwiftUI creation shell covering all six workflow stages.
- Adaptive layout tokens, Dynamic Type-compatible text, and labelled progress/status feedback.
- Autosave and most-recent-project restoration through the persistence protocol.
- Saved-project catalogue UI with new/continue entry points and recovery messaging.
- In-memory project storage for previews and isolated tests.
- Explicit PhotoPicker/PhotoKit-facing protocols without broad photo permission dependencies.
- Detection and reporting of corrupt or future-version project files.
- Root coordination between the project catalogue and creation journey.
- Rename and confirmed-delete project management; deletion never touches original photos.
- Fake photo selectors covering cancellation and permission-denied behaviour.
- Dependency-injected hero and source selection in the creation session.
- Explicit picker progress, cancellation, unavailable-asset, permission, and iCloud failure states.
- A versioned project-migration pipeline with a tested version-zero to version-one migration.
- Safe rejection of corrupt documents, unknown migration paths, and future schema versions.
- Source-set validation for maximum size, duplicate identifiers, and access-mode origin.
- Oversized selections are rejected visibly rather than silently truncated.
- Analytics values are constrained to coarse allowlists; filenames and free text are rejected.
- Creation-flow analytics tests prove that photo identifiers never enter emitted events.
- Reusable hero and source-review thumbnail view models with bounded pixel requests.
- Explicit idle/loading/loaded/failed thumbnail states and retry of failed iCloud assets.
- Persistent add/remove source-review operations with combined-set revalidation.
- A readiness state showing whether the project meets the minimum source count.
- Thumbnail state is preserved when the reviewed source collection changes.
- Functional hero and source-review SwiftUI screens backed by injected services.
- Cross-platform thumbnail rendering for iOS and macOS package validation.
- Lazy per-cell thumbnail loading, add/remove controls, retry, and readiness messaging.
- An isolated `MosaicApplePhotos` adapter for explicitly selected `PhotosPickerItem` values.
- App-controlled picker-asset caching with bounded ImageIO JPEG thumbnail generation.
- Selected-photo imports produce opaque app identifiers rather than exposing library identifiers.
- Multi-photo imports are atomic: failed transfers and cache writes leave no partially imported selection behind.
- The `PhotosPickerItem` bridge is compiled only for iOS/iPadOS; its cache and ImageIO components remain covered by macOS CI.

Photo-library integration remains behind the next platform boundary. The current hero and source buttons deliberately use fixture references so the complete navigation/persistence shell can be compiled and tested before PhotoKit is introduced. The package cannot be compiled locally because Apple Swift/Xcode tooling is unavailable on Windows; GitHub Actions provides the macOS build gate.

## Initial macOS setup

1. Create a SwiftUI Multiplatform/iOS app named `MosaicMemories`, targeting iPhone and iPad.
2. Choose the deployment target only after the Phase 1 benchmark spike.
3. Use local Swift packages or framework targets for:
   - `MosaicEngine`
   - `PhotoLibrary`
   - `Persistence`
   - `Features`
   - `Privacy`
4. Keep Apple frameworks behind protocols so unit tests use deterministic fixtures.
5. Add unit, golden-image, integration, and UI test targets before feature work.
6. Record architectural decisions in `docs/decisions/` using the template below.

The first vertical slice is manual: choose hero → choose selected photos → review → preview → inspect/replace → export. Smart Library remains feature flagged until its own evidence gate passes.
