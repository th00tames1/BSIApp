# Target tree field feedback acceptance record

Status: **PASS — all six requested review roles approved**.
Implementation: v0.4.3+15, based on 9bac08a. Review date: 2026-10-21.
This file records the requested six-role review. The roles are independent
software review perspectives, not a claim that a human forestry professional
performed a field inspection.

## Required outcomes

1. Separate neighbouring or background trees from the chosen target when their
   detections overlap. The original field photo for this report is unavailable;
   synthetic evidence and an effective correction path are required, and that
   evidence must not be described as validation on the missing field photo.
2. On original **013 east**, retain the pole-side target and reject the separate
   left/background trees. The overlay and every measurement must use the selected
   tree, including clipping soot to that tree.
3. On original **001 east** and **004 south**, retain both visible forks of the
   same tree and their common base without filling the sky between the forks or
   admitting separate side trees.
4. Explicit target selection must select the mask at the tapped point even when
   bounding boxes overlap. Corrections must remain effective after saving and
   reanalysis. An unresolved merged mask needs an effective correction route;
   merely asking the user to tap the same merged instance is insufficient.
5. Preserve measurement consistency: selected tree, soot intersection, overlay,
   DBH width, soot dimensions, BSI and saved results must agree. Additional crop
   inference must preserve source coordinates, pole scale and manual corrections.
6. Demonstrate regression safety on existing tests and field examples. Record
   added inference cost and distinguish desktop model replay, Flutter app tests,
   and physical Android validation.

## Evidence required before approval

- Production `AnalysisService` replay of the three original photos using the
  shipping model, source-coordinate include/exclude annotations, and retained
  masks/overlays for independent visual review.
- Synthetic decoder tests for overlapping boxes, explicit mask selection,
  detached forks, separate trees, genuinely joined/overlapping masks, and soot
  outside the selected target. Any correction route needs app-level coverage.
- Crop/letterbox coordinate and scale tests if ROI inference is introduced;
  failures or empty rescue masks must retain a previously valid result.
- A whole-image review in addition to sparse probe points. Passing probes alone
  does not establish that no other tree was added or that full forks were kept.
- Passing applicable analyzer/tests and an Android build. If physical-device
  execution is unavailable, state that explicitly rather than claiming it ran.

## Six-role decision ledger

| Role | Status | Evidence / unresolved requirements |
| --- | --- | --- |
| Code review | PASS | Final source reviewed; out-of-range DBH fixed; component, attachment, exclusion and measurement guards checked. |
| Photo analysis | PASS | Independently inspected four originals, complete final masks and overlays; 013 E, 001 E, 004 S, 014 W passed. |
| Algorithm | PASS | Re-ran 24 algorithm/DBH tests; gap protection followed by anchored flood, separate stem calibration reference verified. |
| App testing | PASS | Production replay 21/21, complete suite 239/239 with 12 opt-in skips, UI 11/11; final APK, matching signature, version and bundled model hashes independently verified. |
| Forestry operator perspective | PASS | Four overlays, measured DBH, correction UI, confirm/undo/cancel and saved reanalysis inspected; software workflow scope only. |
| Supervisor | PASS | Independently audited other five approvals, full-photo artifacts, source, logs, APK and explicit scope limits; final decision recorded 2026-10-21. |

Approvals must name the reviewed revision or exact final files and evidence.
Any later relevant code change invalidates affected approvals until rechecked.


## Final verification evidence

- `flutter analyze --no-pub`: no issues.
- Complete default suite: **239 passed, 12 opt-in private-photo tests skipped**.
- Separate production replay and geometry run: **21 passed**, using the shipping
  main, helper and pole ONNX assets and Dart production preprocessing/analysis.
  Only model execution is bridged to desktop Python ONNX Runtime for this test.
- Algorithm/DBH focused run: **24 passed**. UI correction and two screenshot
  renders: **11 passed**. Screenshots include actual 013 E at Korean 393px and
  English 320px with 1.5 text scale. The photo remains fixed as controls scroll.
- Local retained logs: `.dart_tool/target_tree_final_all_tests.log`,
  `target_tree_final_field.log`, `target_tree_final_analyze.log`,
  `target_tree_final_algorithm_tests.log`, `correction_preview_final.log`.
- Four real-photo outputs and calculation evidence:
  `.dart_tool/target_tree_final_field`, including `review_metrics.md`.
  Independent visual decision: `.dart_tool/photo_review/REVIEW_FINAL.md`.
  Private originals and generated photo artifacts are not committed.

For actual 004 S with measured DBH 35cm, the original 9-proto-column stem gives
102.857px/m; the physical breast-height row differs from 1.3m by less than one
mask row. Soot height is 2.216667m, visible stem height 4.938889m, BSP below
0.872381. Measured DBH stays 35cm, automatic DBH stays null to avoid circular
estimation. One-face-to-four-face integration gives BSI 7.735111.

Each normal replay executed one primary full-frame, one primary upper ROI,
one helper and one pole inference. Full desktop CPU analysis took about
2.7–3.7 seconds including preprocessing and artifact writes; the first includes
cold load. This is not an Android latency measurement.

## Limits retained in the decision

The original first overlap photo is unavailable. Its exact real-world outcome
is unverified; synthetic connected/overlapping masks and the effective manual
exclusion route are the evidence for that report. The supplied known cases
are regression data used during development, not an independent holdout set.
No all-species or all-crossing automatic separation guarantee is claimed.
No physical Android device is connected; installation, gloves/sunlight operation
and device latency have not been tested. The forestry role is an independent
software review perspective, not a human forestry field certification.


## Final Android artifact

Release build: `flutter build apk --no-pub --release --target-platform android-arm64`.
Final build succeeded in 92.7 seconds after the final UI source change.
Package `com.bsi.bsi_field2`, version `0.4.3`, versionCode `15`, minSdk 24,
targetSdk 34. `libapp.so` is arm64-v8a; other ABIs in ONNX plugin libraries
do not make this a universal Flutter application.

- APK bytes: `165537474`.
- APK SHA-256: `c27b3c49ed4d287493d9ca8bbc49de1bd27a1cd62725db03c973736ab5e45a44`.
- Valid signing certificate SHA-256, same as existing BSI_app2 distribution:
  `b3d670e91f63a2afa3d388d21292f14b0e571d6d9cb5d7ba2887389446ecbcd9`.
- All three ONNX assets in the ZIP exactly match source hashes; main model
  unchanged and helper provenance recorded in `target_tree_models.md`.
- Local evidence: `.dart_tool/release_v0_4_3_build_final.log`,
  `release_v0_4_3_verification.json`, `release_v0_4_3_signature.log`,
  `release_v0_4_3_badging.log`, and independent
  `target_tree_apk_final_*.log`.

Approved algorithm source SHA-256:

| Source | SHA-256 |
| --- | --- |
| `lib/src/services/seg_decoder.dart` | `8dad3bfedb9fd60b1516163b570eeb30a4eeee8365a14464ad668fe85330d431` |
| `lib/src/services/analysis_service.dart` | `f3fcaaf28d2cd511401005599268f0f42cf43c9304e0acb7031b43b1ff0965e7` |
| `lib/src/services/target_tree_rescue.dart` | `31fe9ab6a9919a2125e7c8a0c37710c5c3618422f8a3ed4b7027c7b68468d69e` |
