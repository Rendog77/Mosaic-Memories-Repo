# Architecture

## Platform boundary

The creation product is native iPhone/iPad software. SwiftUI provides one adaptive UI; PhotosUI/PhotoKit sits at the photo boundary. A browser is not the MVP because it cannot offer the persistent, privacy-sensitive Apple Photos workflow required by Smart Library.

There are two honest access modes:

- **Selected Photos:** PhotosPicker gives the app only the items explicitly selected. This is the default and lowest-friction path.
- **Smart Library:** explicit PhotoKit read access lets the app inspect authorised assets and build its own local index. Limited, denied, revoked, iCloud-only, and changed-library states are first-class cases.

PhotoKit must not be treated as an API to Apple Photos' private semantic or named-person index. Vision detects faces but does not establish identity. Any future user-labelled subject matching needs conservative thresholds and correction controls.

## Proposed modules

- `App`: composition root and navigation.
- `Features`: hero selection, source review, editor, export, Smart Library.
- `PhotoLibrary`: PhotosPicker/PhotoKit adapters behind protocols.
- `MosaicEngine`: descriptors, candidate retrieval, assignment, and rendering.
- `Persistence`: project recipes and a versioned, rebuildable local index.
- `Privacy`: permission education, deletion, and analytics allowlist.

## On-device stack

- SwiftUI for UI.
- Core Image, Accelerate/vImage, and Metal for previews/compositing.
- Vision for broad classifications, feature prints, faces, and quality signals.
- Core ML only if measured product needs exceed Vision.
- SwiftData for projects; SQLite is preferred for a large versioned semantic index.
- BackgroundTasks for resumable indexing when the system grants time.

## Indexing pipeline

1. Fetch authorised asset metadata; apply cheap date/location/media filters first.
2. Analyse bounded thumbnail batches, never originals unnecessarily.
3. Compute labels/confidences, feature vectors, face count, blur/exposure, and duplicate hashes.
4. Checkpoint versioned records and respond to PhotoKit changes.
5. Rank results using hard filters, semantic score, quality, and diversity.
6. Provide recent/favourite results progressively; never block creation on indexing the whole library.

## Production mosaic engine

The prototype uses weighted average RGB and a greedy repeat window. Production should evolve toward Lab colour histograms, luminance and edge descriptors, crop-safe regions, approximate candidate retrieval, and a global assignment pass that penalises adjacency, overuse, similar sequences, destructive crop, and heavy colour alteration.

Rendering has three levels: instant thumbnail, interactive medium preview, and strip/tile-based full-resolution export. Save a deterministic, versioned project recipe so previews and exports reproduce the same assignment.

## Privacy and services

Normal selection, indexing, generation, and export remain local. Store identifiers and derived descriptors—not copied originals—and make the rebuildable index erasable. Exclude hidden/sensitive content by policy where APIs permit. Do not log library-derived data.

An optional service may later manage entitlements, print orders, crash telemetry, or exceptional renders. Cloud upload is a separate explicit consent step covering selected assets, vendor/region, retention, and deletion.

## Print rule of thumb

Design backwards from visible tiles. At 300 DPI a 6 mm tile is about 71 pixels. A 60 × 40 cm print using 6 mm square tiles is about 100 × 67 cells and roughly 7,100 × 4,700 pixels. Preserve colour profiles supported by the print vendor and render in strips to control memory.

