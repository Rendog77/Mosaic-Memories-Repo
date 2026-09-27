# Gate G6 — Export quality

**Decision:** Open. Automated reference-export validation is implemented; human inspection and a physical print remain required.

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

## Physical-print requirement

Print at least one representative 300 PPI export at the size reported by the application. Record printer or service, paper, requested dimensions, actual dimensions, reviewer, date, normal-distance hero recognition, near-distance source recognition, colour observations, cropping, and any defects.

Synthetic images prove the export pipeline rather than photomosaic quality. Gate G6 remains open until the artifact review passes and a representative consented or appropriately licensed project passes the physical-print rubric.
