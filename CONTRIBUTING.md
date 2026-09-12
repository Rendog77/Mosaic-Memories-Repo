# Contributing

Keep changes aligned with the gated build plan. A feature is not complete until its tests and relevant failure states are covered.

- Never commit personal photos, PhotoKit identifiers, derived face/semantic data, secrets, or production exports.
- Keep the mosaic recipe and engine version deterministic so previews and final exports can be reproduced.
- Add an ADR for choices that affect privacy, persistence, platform support, permissions, rendering, or external services.
- Prefer test fixtures that are synthetic, licensed, or explicitly consented.
- Treat Smart Library as optional and feature flagged until Gate G7 passes.

Pull requests should state the user outcome, evidence/tests, privacy impact, accessibility impact, and build-plan gate affected.

