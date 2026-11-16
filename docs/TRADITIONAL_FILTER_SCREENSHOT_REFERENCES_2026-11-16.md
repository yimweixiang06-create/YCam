# Traditional photo filters: screenshot reference check (2026-11-16)

User-provided camera UI screenshots:

| Source | Appearance |
| --- | --- |
| IMG_3120, ORIGINAL | white paper and marble baseline |
| IMG_3122, VIVID WARM | noticeably warm orange/peach, brighter |
| IMG_3123, VIVID COOL | cooler cyan/blue white paper |
| IMG_3124, DRAMATIC | neutral, lower saturation, stronger tonal structure |
| IMG_3125, DRAMATIC WARM | warm brown/sepia with deeper shadows |
| IMG_3127, MONO | neutral grayscale |
| IMG_3128, SILVERTONE | lifted highlights and gently warm gray |
| IMG_3129, NOIR | higher-contrast grayscale |

The test file `tools/verify_traditional_filter_refs.py` stores only aggregate
median RGB values from five large image regions for each screenshot; no
personal photographs are added to the GitHub repository.

These are **camera screenshots**, not camera RAW reference files; frame
registration, time, exposure, device color management and white balance
are not controlled. The test uses tolerant matching and image-direction
checks. It cannot certify identical Apple proprietary filter appearance.

Traditional filters are evaluated as a **separate color path**, not mixed
with YCam's 28 Photographic Styles, Fuji LUTs or dot-palette changes.
All iOS Photographic Style constants and UI were left untouched.

In original color mode, the automatic white balance uses the camera's
hardware `.continuousAutoWhiteBalance`. Reapplying the mode after
starting/reconfiguring the camera prevents stale manually locked modes
across lens changes, but does not promise every mixed-light scene is
perfectly neutral. Physical iPhone verification is still required.
