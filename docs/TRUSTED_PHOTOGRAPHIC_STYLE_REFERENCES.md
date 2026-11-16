# YCam – Trusted photographic-style reference candidates (2026-11-16)

**This is a catalog of potential reference *sources*, not a claim that their images were downloaded, licensed, calibrated against or verified as pairs.** Source links may be copyrighted. Do not redistribute or bundle third-party images without permission.

## Priority source list

| Priority | Publisher | Source | Responsible use |
|---|---|---|---|
| 1 | Apple Support (official) | https://support.apple.com/en-my/guide/iphone/iph629d2cd37/27/ios/27 | Verify Photographic Styles UI, gestures, naming, controls. Does not publish private LUT coefficients. |
| 1 | Apple Support official video | https://www.youtube.com/watch?v=98IIDpiBs0U | Visually check camera control interaction and control meanings; video screenshots are not reference pairs. |
| 1 | Apple Photos guide | https://support.apple.com/en-my/guide/iphone/iphb08064d57/27/ios/27 | Verify editing behavior, visible values, supported styles. |
| 2 | AppleInsider | https://appleinsider.com/articles/24/10/03/iphone-16-review-bold-colors-new-buttons-promises-for-the-future | Multi-style comparison of a similar stationary subject. Use for directional visual review only unless original full-resolution data and usage permission are obtained. |
| 2 | MacRumors | https://www.macrumors.com/guide/iphone-16-photographic-styles/ | Reference named Photographic Styles, interactions, and model differences. |
| 2 | Digital Trends | https://www.digitaltrends.com/phones/photographic-styles-is-the-best-iphone-feature-i-have-used-in-years/ | Side-by-side comparisons under several scenes; not a guaranteed raw original/reference dataset. |
| 2 | DXOMARK | https://www.dxomark.com/apple-iphone-16-camera-test/ | Understand rigorous test-chart/lab lighting protocols; their proprietary measurements and photos are not an open calibration dataset. |

## Strict verification gate before automated calibration

1. **Grade A: paired truth** — same source scene/file or calibrated chart, verifiable default/standard reference and target Photographic Style, original full-resolution images, exact model, style name, tone/color/intensity, lighting/white balance, HDR/profile/gamma and editing history. Original owner permission/compatible license required for downloads or repository storage. These alone may be used to estimate target color error and fit parameters.
2. **Grade B: repeated scene comparison** — a static scene under similar light but different exposures/captures. May inform **qualitative** shifts only after registration and exposure normalization; do not call the resulting Delta E a ground-truth target error.
3. **Grade C: screenshot/video/publisher web JPEG** — useful for layout, interaction and approximate qualitative appearance. Browser compression, color profiles and editing create unknown biases. Do not modify LUT automatically based on these.
4. **Grade D: unrelated or unverified rights/content** — exclude from target fitting and sample count.

Quality thresholds are per *effect* and per scene, not just total images. A bulk set of 200 unpaired photos proves no Apple/Fuji/Kodak accuracy. Report separately: (a) distinct licensed images used for stability checks, (b) distinct verified Grade-A original/target pairs per effect, (c) usable coverage by skin/sky/foliage/architecture/night/gray and palette corners, (d) baseline and proposed ΔE on independent holdout pairs, and (e) clipping/skin-tone regressions. Never claim a new calibration if Grade-A count is zero.

When Grade-A pairs and permissions are available, implement parameter fitting on a separate branch, validate independent holdout ΔE and preservation of grayscale/skin quality, review provenance, then allow GitHub Actions to build and publish a new unsigned IPA *only if proven better*. Do not re-package the same old IPA under a new version. Physical iPhone installation still needs signing.
