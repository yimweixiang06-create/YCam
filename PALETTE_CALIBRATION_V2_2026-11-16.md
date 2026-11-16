# YCam palette v2 verification (2026-11-16)

Scope: live image, palette cursor, and palette drag feedback only. Unrelated layout unchanged.

## Grounded references

- User-supplied video: ScreenRecording_11-16-2026 9-50-36 AM_1.mp4.
- Apple iPhone Photographic Styles: https://support.apple.com/en-mide/guide/iphone/iph629d2cd37/ios
- Core Image gamma curve: https://developer.apple.com/documentation/coreimage/cifilter-swift.class/gammaadjust()
- Core Image vibrance preserves skin-tone colors: https://developer.apple.com/documentation/coreimage/cifilter/3228429-vibrance

This is YCam's own approximation; Apple does not publish the private Photographic Styles coefficients.
The recorded source frames are a reference and were not mistaken for raw unprocessed sensor data.

## Deterministic 2D controls

- x=(color+100)/200: from -100 (reduced saturation) to +100 (increased chroma and vibrance)
- y=(100-tone)/200: from +100 (lifted midtones) to -100 (deeper midtones)
- strength=0 means identity, 100 means full strength
- gamma power: 1 - 0.28*tone
- exposure EV: 0.08*tone
- contrast: 1 - 0.14*tone
- saturation: 1 + color*(positive ? 0.62 : 0.68), min 0.25
- vibrance: 0.38*color

Tone and color above are each normalized to [-1,+1] and multiplied by strength. GPU filters are applied on the existing live style output. Center is neutral, and the controls do not rebuild the 33^3 color cube during pointer drags.

## Numeric verification

25 combinations of tone and color at {-100,-50,0,+50,+100}: pass.
No axis coupling: pass. Monotonic top-to-bottom and left-to-right: pass.
Centered neutral identity: pass. Strength=0 neutral: pass.
Valid bounds and no division by zero for the input grid: pass.
Xcode iOS release build: see GitHub Actions workflow triggered by this commit.

Preview and finished capture share FilterEngine's processing path. Final appearance must still be tested on a physical iPhone under more than one light source.
