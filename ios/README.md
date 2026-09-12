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
