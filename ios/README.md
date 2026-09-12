# Native iOS/iPadOS app

This folder contains the platform-independent production foundation as a Swift Package. Do not hand-author an `.xcodeproj` on Windows: create and validate the application target with the installed Xcode version on macOS.

## What is available now

- Versioned, Codable project recipes and asset references.
- Protocol boundary for the mosaic engine.
- Atomic JSON project persistence behind an actor and protocol.
- Typed, allowlisted analytics events that cannot accept arbitrary fields.
- The manual creation workflow state and source-count validation.
- XCTest coverage and a macOS GitHub Actions workflow.

These components are intentionally free of PhotoKit and UIKit so they remain deterministic and testable. The package has not been compiled locally because Apple Swift/Xcode tooling is unavailable on Windows.

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
