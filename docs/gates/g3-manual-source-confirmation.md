# Gate G3 — Manual source confirmation

**Decision:** Passed on 2026-09-24 for selected-photo mode on the iOS 17 simulator floor.

## Evidence

- The application presents Apple's system photo picker without requesting broad photo-library permission.
- iPhone Simulator UI tests select a hero, apply framing, select multiple source photos, review thumbnails, add another photo, and remove a photo.
- A CI fixture containing one privately cached hero and 100 privately cached source assets resumes at source review, reports that it is ready, confirms successfully, and reaches preview.
- Confirmation checks that every cached asset is still available and remains in review when an asset is missing.
- Source selections and explicit confirmation state survive persistence; interrupted partial selections return to review rather than bypassing confirmation.
- Unit tests cover insufficient, duplicate, excessive, missing, cancelled, and transient-transfer cases as well as confirmation rollback after a failed save.

## Scope and remaining risk

This gate proves the account-free selected-photo journey and the 100-photo confirmation boundary in hosted simulator CI. It does not validate real iCloud downloads, memory and thermal behaviour, very large libraries on physical devices, or future full/limited PhotoKit access. Those remain deferred Gate G1 and hardening work. The current dimension ceiling is a safety bound pending device measurement.
