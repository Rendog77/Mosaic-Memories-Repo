# Mosaic Memories

**Turn the photos you never look at into one picture you will keep.**

Mosaic Memories is an iPhone/iPad-first product for creating personal photomosaics. A user chooses a hero image, selects or describes the memories that should form it, reviews the source set, creates the mosaic on-device, and exports artwork suitable for sharing or printing.

This repository currently establishes the product baseline and includes a runnable desktop proof-of-concept for the mosaic engine. The production app is planned as a native SwiftUI application; development of its Xcode project must take place on macOS.

## Repository map

- `docs/product-brief.md` — product promise, users, MVP boundary, requirements, and measures.
- `docs/architecture.md` — native architecture, Apple-platform constraints, privacy, and engine direction.
- `docs/build-plan.md` — phased execution plan and release gates.
- `prototype/mosaic.py` — dependency-light command-line photomosaic generator.
- `tests/test_mosaic.py` — deterministic unit and integration tests for the prototype.
- `ios/README.md` — intended native app/module layout and first macOS setup steps.

## Run the prototype

Requires Python 3.11+.

```powershell
python -m pip install -e .
python prototype/mosaic.py path\to\hero.jpg path\to\source-photos output\mosaic.jpg
python -m unittest discover -s tests -v
```

Useful controls:

```powershell
python prototype/mosaic.py hero.jpg photos mosaic.png --columns 70 --tile-width 40 --repeat-window 12 --overlay 0.12
```

The source folder represents the already-filtered result of a future instruction such as “use photos of my dog from the past year.” The prototype proves only the final image-composition stage; it does not claim to validate PhotoKit access, semantic indexing, interaction design, or print fulfilment.

## Current milestone

The repository has entered **Phase 2 foundation work**. Phase 1's Apple-device spikes were explicitly deferred because the current environment is Windows-only; their gate remains open. The Swift domain modules, persistence contract, workflow state, privacy-safe analytics, tests, and macOS CI are scaffolded, while the SwiftUI application target still requires Xcode/macOS.
