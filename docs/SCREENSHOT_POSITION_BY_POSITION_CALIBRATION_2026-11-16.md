# Screenshot position-by-position photographic style calibration (2026-11-16)

## User reference capture evidence

The user previously supplied iPhone camera screenshots with the style palette
white dot at left-top, right-top, center, left-bottom, right-bottom, and
several intermediate positions. 45 images are now associated with 6 styles
in a contact sheet and analyzed at four stable scene regions (white paper
center/lower, wood cabinet, floor).

The white cursor's position was identified from the screenshots in the 11 x 11
dot region. Some actual displayed tone/color values do not exactly equal the
nearest dot, e.g. 95 rather than 100; the audit labels are grid *estimates*,
not an OCR-verified copy of the display. Typical displayed style strengths:
Gold 85, Cool Rose 100, Cool 75, Rose Gold 75, Vibrant 100, Neutral 100.

See `calibration/iphone_screen_tone_and_chroma_45_2026-11-16.json` for six
independent shadow/midtone/highlight and left/right chroma parameters.
In the native screenshots, Gold color -100 with upper versus lower tone
changes white paper luminance 93.5% -> 86.3%, while wood changes 28.0% -> 5.6%.
A global exposure or gamma cannot correctly reproduce both simultaneously.

## Measured and simulated iterations

The old per-style global gamma/exposure adjustment produces a mean 14.74/255
luminance MAE on **leave-one-screenshot-out** prediction of the four reference
regions. A conservative five-point tone-curve simulation fitted to the other
screenshots produces 6.11/255 on the same check (six named groups, 45 source
images). This is *not* Apple-vs-YCam color accuracy. We don't have corresponding
YCam photos from the same scene, sensor, and AE/AWB settings. Full RGB
colorimetry and contrast were not validated, and actual Core Image CIToneCurve
uses spline interpolation; the Python proxy is piecewise linear.

## Changes to actual image pipeline

For screenshot-backed styles (Gold, Cool Rose, Cool [name provisional],
Rose Gold, Vibrant, Neutral), use native `CIToneCurve` with individually
fitted shadow at 0.18, midtone at 0.55, highlight at 0.90, and fixed
(0,0)/(1,1) black/white endpoints. This prevents global blown-out whites.
Each style also uses its own measured left/right chroma response. A
continuous palette strength scale allows nearly monochrome far-left Cool
even when the displayed palette strength is 75.

Other 22 styles, including Pearl, retain their separate conservative
response from the previously successful build; the newer Pearl safe
highlight/exposure fix is preserved, not undone.

The original YCam UI/glass, photo sensor controls, 10 traditional filters
and film LUT files are unchanged. Only the Core Image style palette math
changes; no new spatial blur, softness, or bloom.

## Next external evidence required

For a reliable real fidelity score, capture the same scene with native Apple
Camera and YCam, preferably fixed exposure and white balance, and compare
white highlights, dark wood, colored objects and texture details. The
current audit demonstrates a reproducible screenshot-based approximation,
not official Apple certification.
