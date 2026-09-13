# Native iOS/iPadOS app

This folder contains the production modules as a Swift Package plus a declarative XcodeGen application specification. Do not hand-author an `.xcodeproj` on Windows: `xcodegen generate` creates it using Xcode-compatible metadata on macOS.

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
- ImageIO thumbnail transforms normalize camera orientation metadata, covered by a rotated-JPEG regression test.
- Selected-photo imports produce opaque app identifiers rather than exposing library identifiers.
- Multi-photo imports are atomic: failed transfers and cache writes leave no partially imported selection behind.
- Native picker imports expose bounded completed/total progress and temporarily disable competing creation actions.
- Active imports can be cancelled without showing a failure; cancellation rolls back every cached file created by the interrupted batch.
- ImageIO validates every selected file before it enters the private cache, with typed unsupported-format guidance.
- Metadata validation rejects non-positive dimensions and images above an injectable 500-megapixel safety ceiling before decoding or caching; the ceiling remains provisional pending device measurements.
- Transfer errors use stable Foundation signals to distinguish cancellation, unavailable items, network-backed iCloud failures, and unknown failures without parsing localized error text.
- Retryable import failures retain the selected picker items for one-tap retry; cancellation, permission denial, and unsupported formats do not offer misleading retries.
- Removing a reviewed source deletes its private cached copy only after the updated project recipe saves successfully; failed saves roll the workflow back.
- An iOS-only `PhotosPickerCreationView` presents native single-item hero and multi-item source pickers and connects imported assets to the creation session.
- An iOS production composition root connects the saved-project library and picker-backed creation flow using separate Application Support directories for recipes and selected-photo copies.
- The `PhotosPickerItem` bridge is compiled only for iOS/iPadOS; CI builds its package scheme for a generic iOS Simulator while its cache and ImageIO components remain covered by macOS tests.
- A universal SwiftUI `@main` application target is generated from `project.yml` and compiled for a generic iOS Simulator in CI.
- CI boots available iPhone and iPad Simulators, installs the application, and verifies both a cold launch and a process relaunch on each device class.
- Simulator smoke tests seed a versioned project recipe and require the production store to recover it on both launches.

The manual path uses SwiftUI PhotosPicker and receives only the items a person explicitly selects; it does not request broad library permission. Apple Swift/Xcode tooling remains unavailable locally on Windows, so GitHub Actions provides package, application, and simulator build gates.

## Initial macOS setup

1. Install XcodeGen and run `xcodegen generate` from this directory to create the universal iPhone/iPad project.
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
