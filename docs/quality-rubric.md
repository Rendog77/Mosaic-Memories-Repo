# Mosaic quality rubric

This rubric turns the two-distance product promise into repeatable measurements while preserving a required human review. The automated harness lives in `MosaicCore` so the same assignment can be evaluated before preview or export rendering.

## Provisional automated thresholds

| Dimension | Measurement | Provisional pass threshold |
| --- | --- | --- |
| Hero likeness | Mean and 90th-percentile CIE76 distance between each hero target and its assigned source, scaled by the unblended portion of the tile | Mean ≤ 18 and p90 ≤ 28 |
| Tile authenticity | Fraction of assignments that reference a confirmed source, scaled by the unblended portion of the tile | ≥ 0.35 |
| Tile diversity | Unique confirmed sources used relative to the usable source/tile count | ≥ 0.60 |
| Local repetition | Consecutive row-major tiles using the same source | ≤ 0.05 |
| Crop safety | Area of the annotated hero-subject bounds retained by the saved crop | ≥ 0.90 |

These thresholds are deliberately versioned in code as `MosaicQualityRubric.provisional`. Changing one requires a decision-log entry with before/after results for the complete golden set.

## Golden-project record

Each of the ten consented projects must record:

- a stable non-personal fixture identifier;
- consent or licence provenance and permitted test use;
- the hero image, confirmed sources, saved crop, recipe, descriptors, and deterministic assignment;
- normalized bounds around the hero subject that must remain inside the crop;
- automated metrics and pass/fail criteria;
- near-distance notes on whether individual source memories remain recognisable;
- normal-viewing-distance notes on whether the hero is immediately recognisable;
- reviewer, device, display scale, engine version, and review date.

Raw personal images must remain in the approved private fixture store. CI may use consented redistributable assets or a derived descriptor manifest that contains no filenames, captions, locations, or other personal metadata.

## Gate policy

Gate G4 requires at least eight of ten consented projects to pass every automated threshold and the human two-distance review. An interrupted preview must also recover without publishing a partial assignment.

The repository currently includes a deterministic ten-case synthetic calibration test. It proves metric calculation, failure reporting, and the 8/10 aggregation rule; it is not evidence that Gate G4 has passed. G4 remains open until the consented projects and review records are supplied.

## Review procedure

1. Generate the preview from a clean cache using the recorded engine version.
2. Confirm the assignment is deterministic by regenerating it with sources in a different input order.
3. Record the automated quality evaluation.
4. At normal viewing distance, rate hero recognition without zooming.
5. At near distance, inspect representative face/edge/background tiles for source recognition, repetition, and unsafe crops.
6. Repeat using the high-resolution export when export rendering is available.
7. Record failures by criterion; do not average a failed dimension away with stronger scores elsewhere.
