# YCam independent photo styles / blown-out Pearl fix (2026-11-16)

The user reported that YCam's Pearl photographic style was overexposed and
visually soft, and asked that **all** photographic styles own independent
recipes rather than sharing a single adjustment.

## Root causes and fixes

1. The previous implementation gave eight named styles custom pad response
   values but all other styles shared a universal fall-back. Now each of
   **28 CameraStyle cases** has its own **six-parameter** response:
   gamma/tone, left/right chroma, upper/lower corner tone compression,
   and tone-axis exposure. Each style has a separate LookRecipe as well.
   Nine Fuji styles retain their **individual source LUT datasets**, with
   conservative LUT complements rather than blank identity recipes.

2. Pearl had `CIGammaAdjust` power around 0.52 at the upper palette edge
   and a negative lower-axis exposure coefficient that accidentally
   **brightened** when dragging down. The new Pearl gamma strength is
   0.072, exposure per signed tone 0.012, and base exposure is -0.015 EV.
   High-white and skin highlights are no longer heavily lifted.

3. No Photographic Style can invoke extra spatial `softness` or `bloom`;
   the source image and JPEG/HEIF quality remain full resolution.
   Live photo and normal video use the same FilterEngine. Intentional
   Portrait-mode depth blur is **independent and still available** when
   the user enables it.

4. Camera preview started with a 900-pixel long edge and capped at
   1050. It now starts at 1200 and can recover to 1450 when the measured
   renderer is fast. Slow frames and high thermal load still trigger
   adaptive downscaling; captured stills are not downscaled.

5. Previous old screenshot-proxy parameters were measured from iPhone
   screenshots with varying camera exposures/AWB, **not Apple/YCam
   paired raw captures**. The original 53 screenshots and 20 Pearl video
   observations remain in calibration data, but those old high-gamma
   values are retained as a historical rejected fit, not an accuracy
   certificate.

## Isolation and limits

- Original UI, frosted glass, dotted palettes and AppleFilter 10
  traditional filters are untouched.
- Normal Photo mode remains sharp. Users can still deliberately enable
  Portrait-mode depth of field, which does blur the background.
- The 28 distinct photo style responses are **engineering estimates**,
  not 28 Apple-certified look replicas.
- iOS compile/CI is a correctness check; paired iPhone photos are
  required to assess actual style fidelity and clipping in real light.
