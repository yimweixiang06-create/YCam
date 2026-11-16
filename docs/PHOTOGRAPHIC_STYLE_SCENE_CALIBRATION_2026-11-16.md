# YCam — photographic style *image* response from user's iPhone references

Date: 2026-11-16. Source: the user-supplied native iPhone camera screenshots of a white sheet, wood cupboards and colored objects (53 control-point screenshot observations), plus 20 frames of their Pearl style video. The original photographic images are **not** uploaded to this repository.

### What is calibrated

The photographed, style-specific tonal response when moving the 2D pad to the top/bottom; how the color axis desaturates towards the left and becomes more saturated on the right; and conservative base-look corrections for Gold, Cool Rose, Cool, Rose Gold, Vibrant, Neutral and Pearl. The vivid blue/white observed in the Vibrant source is reflected in its cooler base recipe. Warm receives an **explicitly provisional** pad-response estimate; its base recipe remains unchanged because those five warmer screenshots did not contain an unequivocal style-name confirmation.

Reference anchors are recorded as *paired screen-capture pixels from the same capture group*, in `calibration/iphone_photo_style_scene_response_2026-11-16.json`, with white-paper and wood surface RGB medians for the four extreme pad positions. The test `tools/verify_photographic_style_scene_refs.py` ensures that each implemented response improves a simple **scene-relative** four-corner error proxy over the old shared response. This compares pixels within the native iPhone screenshot set, not output from YCam.

### Limitations (do not overclaim)

**Not** pixel-identical Apple rendering, not a ColorChecker-based calibrated Delta E result, and not an Apple photographic-style RAW processing port. Same lighting and source sensor RAW files, locked camera exposure and AWB, YCam paired captured frames, and several scenes per style are still missing. The screenshot-only baseline and viewfinder compression may induce exposure/white-balance bias. A successful GitHub build proves code compiles; it does not validate actual iPhone camera color accuracy. Style names for Cool and Warm are provisional.

### Preserved behavior

The original YCam glass/UI is untouched. Traditional `AppleFilter` recipes and film LUTs are unchanged and cannot mix with photographic styles. The default neutral pad remains 0/0, intensity 100. The user's top-half +3% / bottom-half −2% zone saturation rule remains. The calibrated styles have no default spatial blur. Preview, still images, Live Photo and video share the same `FilterEngine` processing path.
