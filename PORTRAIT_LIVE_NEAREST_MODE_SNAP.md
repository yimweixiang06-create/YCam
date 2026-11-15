# YCam 1.1 (10) — Portrait Live Photo and nearest-stop mode selection

## Mode switch
- UIKit UIControl maintains direct CALayer movement without re-rendering the entire camera view.
- Horizontal tracking locks after a 3pt start distance; slight vertical movement cannot interrupt following.
- On release, snap **to the closest mode** using rounded continuous position. A short drag that stays nearer the current mode returns to it.
- Tap directly chooses the closest of the three visible segments.
- Photo long press only begins on the Photo segment, reducing accidental cancellation of video/portrait swipes.
- No image-processing or AVFoundation session changes until a completed mode selection.

## Portrait Live Photo
- Portrait mode can enable Live Photo on devices supporting AVCapturePhotoOutput Live Photo, when HEIF and max effective photo dimensions <=24MP and native 4:3 crop.
- The key frame receives the custom portrait background blur; paired movie receives color style rendering (not per-frame portrait segmentation). This is not an exact clone of Apple's proprietary camera pipeline.
- HEIF Max/RAW and incompatible capture devices remain unavailable, and the app never silently downgrades image resolution.
- Availability must be verified on iPhone; an Xcode build alone cannot demonstrate that particular combinations will be accepted by each device.

Apple reference:
https://support.apple.com/guide/iphone/take-live-photos-iph17471d6de/27/ios/27
https://support.apple.com/en-gb/guide/iphone/iphd8dbb3291/26/ios/26
https://developer.apple.com/documentation/avfoundation/avcapturephotooutput
