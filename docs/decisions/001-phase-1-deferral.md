# ADR-001: Defer Apple-device technical spikes

- Status: Accepted risk
- Date: 2026-09-12
- Owners: Product / Engineering

## Context

The current development environment is Windows-only. Xcode, SwiftUI previews, PhotoKit, iOS simulators, signing, Instruments, and physical iPhone/iPad profiling require macOS. The product owner chose to proceed with Phase 2 preparation before those measurements.

## Decision

Proceed with the platform-independent Phase 2 foundation as a Swift Package: domain models, module boundaries, project persistence contract, creation workflow, privacy-safe analytics types, tests, and macOS CI. Do not claim Gate G1 or Gate G2 has passed. Do not lock the deployment target beyond the provisional package minimum or implement performance-dependent engine choices.

## Consequences

- Windows work can establish reviewable architecture and reduce later setup time.
- The universal SwiftUI application shell, PhotoKit adapters, simulator/device tests, signing, accessibility validation, and persistence-in-app proof remain blocked until macOS execution is available.
- The provisional iOS 17 target may change after measurement.
- Performance, thermal behaviour, iCloud handling, and high-resolution export feasibility remain open risks.

## Evidence required to revisit

- Successful `swift test` on macOS.
- Xcode build on representative iPhone and iPad simulators.
- Physical-device PhotoKit and rendering benchmarks from the deferred Phase 1 plan.

