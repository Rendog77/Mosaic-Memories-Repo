# Gate G6 — Export quality

**Decision:** Open. Automated reference-export validation and human artifact inspection pass; a representative physical print remains required.

## Automated evidence

Every successful `iOS core` workflow publishes a `mosaic-reference-exports` artifact for 14 days. It contains ten synthetic mosaics and `reference-export-report.json`.

The matrix covers:

- five PNG and five quality-controlled JPEG files;
- square, portrait, landscape, wide, tall, banner, and larger-grid layouts;
- 200, 240, 300, and 360 PPI metadata;
- hero-likeness values from 0% to 20%; and
- assignments containing between 1 and 20 tiles.

The test reopens every encoded file and verifies its type, dimensions, RGB colour model, density metadata, byte count, and sampled tile agreement with a preview rendered from the same deterministic assignment.

## Human artifact review

1. Open the successful GitHub Actions run and download `mosaic-reference-exports` from **Artifacts**.
2. Confirm that the ZIP contains ten images plus the JSON report.
3. Open every image in an independent image viewer; record any unreadable file, visible seam, shifted tile, unexpected crop, colour cast, or JPEG artifact.
4. Compare the five matching layout families across PNG and JPEG where applicable and confirm that format compression does not change tile placement.
5. Retain the workflow URL, reviewer, display, scale, date, and findings in this document before changing the gate decision.

### Synthetic artifact review — 2026-09-29

- **Workflow:** [iOS core #85](https://github.com/Rendog77/Mosaic-Memories-Repo/actions/runs/36567444869), commit `758b0ab`
- **Artifact:** `mosaic-reference-exports`, GitHub digest `sha256:eb5e44525712b4522d2ec01f76d4f1b8a7a48a2e08daa9ca37726a84be2d1f0c`
- **Reviewer:** Product owner (`Rendog77`), following Codex-assisted technical and visual inspection
- **Viewer and display:** Codex image viewer using a 1,560 × 4,200 contact sheet; every source file was also decoded independently with Windows System.Drawing
- **Scale:** nearest-neighbour 3× enlargement for the visual pass, plus native-dimension decoding
- **Coverage:** all ten exports and `reference-export-report.json`; five PNG and five JPEG files across square, landscape, portrait, wide, tall, banner, and grid layouts
- **Result:** Pass for the synthetic artifact matrix, confirmed by the product owner. Every file opened, matched its reported dimensions and density, and showed complete row-major tile geometry. No unreadable file, missing or shifted tile, unintended seam, colour cast, or material JPEG artifact was observed. PNG edges remained exact; the JPEG cases retained placement with only the expected encoded channel variation reported by CI.
- **Scope:** The solid-colour fixtures make geometry and encoding defects conspicuous but cannot establish crop quality, photographic colour fidelity, two-distance recognition, or print quality. Those require consented or appropriately licensed projects and the physical-print evidence below.

## Physical-print requirement

Print at least one representative 300 PPI export at the size reported by the application. Record printer or service, paper, requested dimensions, actual dimensions, reviewer, date, normal-distance hero recognition, near-distance source recognition, colour observations, cropping, and any defects.

Synthetic images prove the export pipeline rather than photomosaic quality. Gate G6 remains open until the artifact review passes and a representative consented or appropriately licensed project passes the physical-print rubric.
