# Product brief

## Product promise

Mosaic Memories lets someone choose the picture they want to recreate and describe the memories that should make it. The experience turns a large, underused personal photo library into one attractive keepsake.

The initial wedge is pet owners: they photograph a recurring, emotionally important subject frequently and have natural gifting, celebration, and memorial occasions.

## Core job

> When I have many photos around a person, pet, trip, or life chapter, help me turn them into one meaningful keepsake without manually sorting everything or learning design software.

## MVP walking skeleton

1. Start without an account.
2. Choose and crop one hero image.
3. Select 100–1,000 source photos using the system picker.
4. Review the source set and remove unwanted images.
5. Generate a recognisable on-device preview.
6. Adjust one “Photo detail ↔ Hero likeness” control.
7. Zoom into the mosaic, inspect a source, and replace an unwanted tile.
8. Save or share a high-quality JPEG/PNG.

Build this complete manual-selection loop before Smart Library. It tests whether the artwork itself creates enough value.

## Smart Library experiment

The first supported grammar is deliberately narrow:

> Use photos of [supported category] from [supported time period].

The app turns this into editable filter chips and clearly groups low-confidence matches. It must never imply access to Apple Photos' private classifications or named-person clusters.

## Product principles

- Outcome before controls.
- Trust before access.
- Explain interpreted filters and uncertainty.
- Keep ordinary creation on-device.
- Optimise for hero likeness at a distance and recognisable memories up close.
- Let users experience value before monetisation.

## MVP requirements

- Native universal iPhone/iPad app, SwiftUI, no account required.
- Selected-photo mode works without full-library access.
- Autosaved local project recipe; generation is cancellable and resumable.
- Square-grid perceptual matching with repeat reduction.
- Zoom, source inspection, single-tile replacement, and likeness control.
- Correct-orientation JPEG/PNG exports and simple print-size guidance.
- Visible index deletion if Smart Library is enabled.
- No images, filenames, prompts, labels, asset identifiers, embeddings, faces, or locations in analytics.

## Explicitly deferred

Android and browser creation; named-person automation; open-ended prompt understanding; cross-device index sync; cloud rendering; video/animated mosaics; irregular layouts; integrated payments, printing, shipping, and social galleries.

## Success and guardrails

The north-star is **meaningful creation rate**: the percentage of new users who export, save, or share within 24 hours.

Initial hypotheses to validate in TestFlight:

- Source set confirmed → preview: at least 70%.
- Preview → meaningful creation: at least 35%.
- Median active time to first preview: under five minutes, excluding downloads/indexing.
- At least 25% of completers inspect a tile.
- Crash-free creation sessions: at least 99.5%.

Before a full build, run 12–15 pet-owner problem interviews and a concierge mosaic test. Evidence sought: repeated unused-photo frustration, willingness to provide/select sources, intent to save/share/print, and demonstrated willingness to pay.

