# Apple camera reliability upgrades for YCam (2026-11-16)

Based on Apple's AVFoundation capture-device exposure and white balance APIs,
Core Image color space options, Core Video image-buffer attachments and
photo-quality output API.

**Changed**
- Explicitly declare Apple's default Core Image extended linear sRGB working
  space and default sRGB output color space; captured stills keep their source
  color profiles in the existing save path.
- Label processed preview/video sRGB pixel buffers and use Metal-compatible
  pixel buffers; no change to unprocessed camera frame metadata.
- Restore continuous auto exposure and auto white balance when entering the
  foreground or recovering from a session error/interruption, and after
  switching lens/mode, without overriding manually selected shutter/Kelvin.
- Prefer continuous auto exposure at tap-to-meter point, with one-shot fallback.

**Already implemented (not duplicated)**
- Photo quality priority, supported max photo dimensions, dropped late frames,
  adaptive preview resolution, segmentation/depth and native per-app languages.

**Not changed**
- Photographic Style look recipes, traditional filters, LUTs, the original
  dotted palette or the YCam frosted glass UI.

A successful build validates compilation and structural tests, not
pixel-identical Apple Photographic Styles or bug-free real-device capture.
