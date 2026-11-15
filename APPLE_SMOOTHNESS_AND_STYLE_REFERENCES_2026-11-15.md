# YCam 1.1 (7) — Motion, palette accuracy, camera responsiveness

Apple Developer references:
- https://developer.apple.com/documentation/xcode/understanding-user-interface-responsiveness/
- https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance
- https://developer.apple.com/documentation/avfoundation/avcapturesession
- https://developer.apple.com/library/archive/technotes/tn2445/_index.html

Reference photos, not Apple's exact proprietary processing:
- https://petapixel.com/2024/09/18/the-apple-iphone-16-pro-pro-max-review-for-photographers/ (skin / texture)
- https://www.digitaltrends.com/phones/photographic-styles-is-the-best-iphone-feature-i-have-used-in-years/ (same-scene color + contrast)
- https://www.tapsmart.com/tips-and-tricks/photographic-styles-guide/ (Cool Rose portraits)
- https://www.dxomark.com/feature-focus-diving-into-the-apple-iphone-16-series-undertones-functionality/ (skin undertones)
- https://www.tomsguide.com/phones/iphones/i-tried-every-photographic-style-on-the-iphone-16-pro-max-this-is-a-game-changer

Changes:
- Raise bottom camera controls 22 logical points from the old position, preserving full-width preview.
- Fast touch-follow on existing UIKit CALayer, label update only when mode changes, 0.17-second ease-out at release.
- 11x11 only-position dot palette; finger must start on the big dot. Neutral 0/0, strength 100 unchanged.
- Coalesce updates of expensive 33^3 filter LUT on serial queue (32ms debounce, cancel stale jobs).
- Conservative recipes for pearl, coolRose, ethereal, luminous, radiant to retain texture and avoid overexposure.

Caveats: Xcode CI compilation is not an iPhone motion benchmark. Apple proprietary scene-adaptive, regional and skin-specific photographic style algorithms are not available via public API.
