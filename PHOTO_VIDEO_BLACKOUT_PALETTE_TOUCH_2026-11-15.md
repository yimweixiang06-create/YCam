# YCam v1.1 build 11 — preview blackout / photographic styles palette

## Photo ↔ video
YCam changes AVFoundation presets for full-quality stills and supported HD/4K video. During this hardware transition, keep the most recent CMSampleBuffer in a small, separate AVSampleBufferDisplayLayer over the live preview.
Remove the held sample only after the new pipeline has enqueued a valid frame and 45 ms of renderer/compositor settling time. A generation token prevents an old completion from hiding a newer hold.
No per-frame CPU image copy. Both photo and video recording output dimensions remain unchanged.

## Style palette
Draw 121 small dots once as a CAShapeLayer. Dragged big cursor uses an independent CALayer with disabled implicit animations. Tap any dot; cursor snaps exactly to dot positions. Publish expensive filter-style changes at no more than roughly 15 Hz during drag; always publish the final position immediately.
Preserve the user's initial Tone 0 / Color 0 / Palette strength 100 and max supported photo dimensions.

## Apple technical references
https://developer.apple.com/documentation/avfoundation/avcapturesession/beginconfiguration()
https://developer.apple.com/documentation/avfoundation/avsamplebufferdisplaylayer/samplebufferrenderer
https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance

Xcode compilation is not an actual device performance measurement. Exposure adjustment and thermal factors may still create a transient visual change.