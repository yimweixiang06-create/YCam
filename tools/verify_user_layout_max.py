#!/usr/bin/env python3
"""Regressions: max-resolution photo, native-position controls and no duplicate portrait/zoom overlays."""
from pathlib import Path
root = Path(__file__).resolve().parent.parent
model = (root / "CameraModel.swift").read_text(encoding="utf-8")
home = (root / "CameraHomeView.swift").read_text(encoding="utf-8")
panel = (root / "ControlPanels.swift").read_text(encoding="utf-8")
ctrl = (root / "CameraControls.swift").read_text(encoding="utf-8")

# Photos always request the device's available maximum; no max/half choice.
assert "PhotoResolutionChoice" not in "\n".join((model, home, panel, ctrl))
assert "halfPhotoDims" not in model and "maximumPhotoTitle" in model
assert "supportedMaxPhotoDimensions" in model
assert "settings.maxPhotoDimensions = maxPhotoDims" in model

# Only pinch gesture zoom remains: no second floating 1x/2x strip.
assert "ZoomPills(" not in home and "struct ZoomPills" not in panel
assert "onPinchChanged" in home and "camera.setZoom" in home

# Portrait lighting's previous hexagon/circle selector was deleted entirely.
assert "PortraitLightingStrip" not in home
assert "lightingStrip(m)" not in home
assert 'Image(systemName: item == items[nearest] ? "hexagon.fill" : "hexagon")' not in home

# Pinning top controls must not shrink or relocate the camera preview.
assert "m.vfTop(pinned: false)" in home
assert "PinnedRow(items: layout.pinned" in home

# The three capture modes are a direct UIKit touch surface, not competing
# SwiftUI Buttons + DragGesture. Only the lightweight indicator follows touch.
assert "private struct CaptureModeStrip: View" in home
assert "private struct ModeStripTouchSurface: UIViewRepresentable" in home
assert "private final class ModeStripTrackingView: UIControl" in home
assert "override func continueTracking(" in home
assert "override func endTracking(" in home
assert "CATransaction.setDisableActions(!animated)" in home
assert "DragGesture(minimumDistance: 0).onEnded" not in home
assert "DragGesture(minimumDistance: 12 * m.s" not in home
assert "camera.setMode(target)" in home
assert "withAnimation(.snappy(duration: 0.25))" not in home
# Swipe direction must match the visible left-to-right order: 视频 / 照片 / 人像.
# Rightward finger movement selects the next item; leftward selects the previous.
assert "stepMode(dx > 0 ? 1 : -1)" in home
assert "show(position: CGFloat(startingIndex) + dx / (68 * scale))" in home
assert "CGFloat(startingIndex) + dx / slot" in home
assert "Int(rawPosition.rounded())" in home
assert "hasHorizontalDrag" in home
assert "nearestTapIndex(at: end.x)" in home
assert "stepMode(dx > 0 ? -1 : 1)" not in home
assert "show(position: CGFloat(startingIndex) - dx / (68 * scale))" not in home
assert "let steps = max(1" not in home
modes = ["视频", "照片", "人像"]
def swipe(index: int, direction: int) -> str:
    return modes[max(0, min(2, index + direction))]
assert swipe(1, +1) == "人像"
assert swipe(1, -1) == "视频"
assert swipe(0, +1) == "照片"
assert swipe(2, -1) == "照片"

# Fixed-size bottom mode bar; frosted, not glossy controls.
assert ".legacyPressScale" not in home and "modeDragging" not in home
assert ".frostedPanel(Capsule())" in home
assert home.count(".frostedPanel(Circle())") >= 2
assert ".frame(width: m.W - 12 * m.s, height: 165 * m.s)" not in home
assert ".position(x: m.W / 2, y: m.H - 82 * m.s)" not in home
assert "无需选择，始终请求最高分辨率" in panel
assert "recordingBadge" in home and "camera.isRecording" in home
print("PASS: max-only photos; pinch zoom; no old lighting overlay; low-latency UIKit mode bar with verified swipe directions; top controls do not resize preview")

# Motion and safe-area regressions (v1.1.7)
metrics = (root / "CameraControls.swift").read_text(encoding="utf-8")
palette_src = (root / "DotPalette.swift").read_text(encoding="utf-8")
engine = (root / "FilterEngine.swift").read_text(encoding="utf-8")
assert "(isLandscape ? 24 : 33) * s" in metrics
assert "var shutterCenterY: CGFloat { isLandscape ? H / 2" in metrics
assert "CATransaction.setAnimationDuration(0.17)" in home
assert "if visualIndex != nearest" in home
assert "private final class DotPaletteTrackingView: UIControl" in palette_src
assert "let columns = 11" in palette_src
assert "dotPosition(col: c, row: r)" in palette_src
assert "dotPosition(col: c, row: r)" in palette_src
# LUTs rebuild only on real style changes; live 2D color controls do not queue cube builds.
assert "pendingBuild?.cancel()" in engine and "milliseconds(16)" in engine
assert "sameBakedStyle(previous.settings, settings)" in engine

# v1.1(8) landscape/portrait/video/long-press/thermal smoke assertions
info = (root / "Info.plist").read_text(encoding="utf-8")
recorder = (root / "VideoRecorder.swift").read_text(encoding="utf-8")
assert "UIInterfaceOrientationLandscapeLeft" in info and "UIInterfaceOrientationLandscapeRight" in info
assert "case .landscapeLeft:" in recorder and "case .landscapeRight:" in recorder
assert "m.isLandscape" in home and "camera.mode == .video { ratio = 4.0 / 3.0 }" in home
assert "onLongPressPhoto" in home and "UILongPressGestureRecognizer" in home
assert "struct DotPalette: View" in palette_src and "Rectangle()" in palette_src
assert "let previous = currentHardwareMode" in model
assert "thermalPreviewLimit" in model and "ProcessInfo.processInfo.thermalState" in model
assert "self.latestMask = result?.mask" in engine

# v1.1 (8): 4:3 video preview, landscape metadata and safe portrait
assert "if camera.mode == .video { ratio = 4.0 / 3.0 }" in home
assert "m.isLandscape" in home
assert "onLongPressPhoto" in home
assert "self.latestMask = result?.mask" in engine
assert "currentHardwareMode" in model
assert "thermalPreviewLimit" in model
assert "UIInterfaceOrientationLandscapeLeft" in info
assert "UIInterfaceOrientationLandscapeRight" in info
print("PASS: camera mode gestures, palette tap, landscape rotation, 4:3 preview and thermal checks")

# Portrait Live Photo is offered on capable HEIF <=24 MP configurations,
# preserving the current photo dimensions; no RAW or HEIF Max downgrade.
assert "camera.mode != .video && camera.livePhotoSupported && camera.livePhotoEnabled" in home
assert "enabled: camera.mode != .video && camera.livePhotoSupported" in home
assert "&& !isPortrait" not in model
assert "&& style.lighting == .off && style.depth < 0.001" not in model
assert "let wantsCompatibleLive = requestedMaxMP > 0 && requestedMaxMP <= 24" in model
assert "settings.maxPhotoDimensions = maxPhotoDims" in model
# Choosing a mode releases only at the closest stop (not forced 9pt stepping).
def nearest_mode(start, translation, slot=68):
    return min(2, max(0, round(start + translation / slot)))
assert nearest_mode(1, +20) == 1
assert nearest_mode(1, +36) == 2
assert nearest_mode(1, -20) == 1
assert nearest_mode(1, -36) == 0
assert nearest_mode(0, +105) == 2

# Build 11: Core Animation frame hold across photo/video preset changes.
preview_src = (root / "CameraPreview.swift").read_text(encoding="utf-8")
assert "private let heldLayer = AVSampleBufferDisplayLayer()" in preview_src
assert "func holdLastFrame(_ sample: CMSampleBuffer?)" in preview_src
assert "func resumeLivePreview()" in preview_src
assert "holdPreviewDuringReconfiguration()" in model
assert "lastDisplaySample = sample" in model
assert "previewHoldGeneration" in model
assert "currentGeneration == latestGeneration" in model

# User-requested original UI restored from commit 2ba8b634; do not re-style.
# Both original style and filter selectors are the small rectangular
# gradient cards (41 × 52) — NOT photos, circular icons, or labels on cards.
assert 'struct SwatchCard: View' in palette_src
assert 'RoundedRectangle(cornerRadius: 11, style: .continuous)' in palette_src
assert '.fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))' in palette_src
assert 'SwatchCard(colors: colors(item), selected: item == selected)' in palette_src
assert 'Image(systemName: symbol)' not in palette_src
assert 'SwatchPhotoRenderer' not in palette_src
# The first dotted backdrop is a lightweight gradient, not a bitmap renderer.
assert 'private enum PaletteColorMap {' not in palette_src
assert 'previews: (Item)' not in palette_src
assert 'shortName: (Item)' not in palette_src
assert 'styleCardPreviews' not in model and 'filterCardPreviews' not in model

# Keep original panels, original style names, exact sizes and custom button.
assert panel.count('cardWidth: 41 * m.s') >= 2
assert panel.count('cardHeight: 52 * m.s') >= 2
assert panel.count('spacing: 8 * m.s') >= 2
assert panel.count('colors: { $0.cardColors }') == 2
assert panel.count('name: { $0.title }') == 2
assert 'shortName: { $0.pickerTitle }' not in panel
assert 'symbol: "circle.grid.3x3.fill"' not in panel
assert 'symbol: "circle.lefthalf.filled"' not in panel
assert 'Text("自定义")' in panel
assert 'DotPalette(point: $camera.styleSettings.point, colors: settings.style.cardColors)' in panel

# Preserve the EXACT FIRST 2026-10-19 gradient backdrop behind white dots.
# Keep high-performance continuous UIKit tracking, original glass panel and ticks.
assert 'struct DotPalette: View' in palette_src
assert 'var colors: [Color]' in palette_src
assert '.fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))' in palette_src
assert 'LinearGradient(colors: [Color.blue.opacity(0.20), Color.clear, Color.orange.opacity(0.20)]' in palette_src
assert 'Image(uiImage: PaletteColorMap.image(' not in palette_src
assert 'Color(red: 0.39, green: 0.33, blue: 0.37)' not in palette_src
assert 'private var guideColors' not in palette_src
assert 'DotPaletteTouchSurface(point: $point)' in palette_src
assert 'private final class DotPaletteTrackingView: UIControl' in palette_src
assert 'private let dotsLayer = CAShapeLayer()' in palette_src
assert 'private let cursorLayer = CALayer()' in palette_src
assert 'lastCommitTime >= 1.0 / 30.0' in palette_src
assert 'let columns = 11' in palette_src and 'let rows = 11' in palette_src
assert 'let ticks = 11' in palette_src
assert 'Color.yellow : Color.white.opacity(0.35)' in palette_src
assert 'dotsLayer.strokeColor = UIColor.black.withAlphaComponent(0.38).cgColor' not in palette_src
assert '.frame(width: 200 * m.s)' in panel
assert 'PanelHeader(m, onBack: onBack, onReset:' in panel
assert 'panel(m, height: m.panelHeight(.custom, drawerCount: count))' in home
assert 'struct PaletteValuesCapsule:' not in panel
assert 'PaletteValuesCapsule(camera:' not in home
assert 'DragGesture(minimumDistance: 0, coordinateSpace: .named' not in palette_src

# User requested EXACT v1.4 palette response and only a mild 6% color boost.
# Never touch the earliest original UI background, cursor or yellow ticks.
assert 'if snap.hasPaletteShift {' in engine
assert 'out.applyingFilter("CIGammaAdjust"' in engine
assert '"inputPower": 1 - 0.10 * tone' in engine
assert 'out.applyingFilter("CIExposureAdjust"' in engine
assert 'kCIInputEVKey: 0.02 * tone' in engine
assert 'out.applyingFilter("CIVibrance"' in engine
assert '"inputAmount": 0.18 * color' in engine
assert 'kCIInputSaturationKey: 1 + color * (color >= 0 ? 0.36 : 0.24)' in engine
assert 'kCIInputContrastKey: 1 - 0.04 * tone' in engine
assert 'r.saturation *= (1.0 + 0.06 * k)' in engine
assert 'out.applyingFilter("CIToneCurve"' not in engine

# Targeted regression: 0% intensity stays unboosted, non-neutral colors get
# exactly 6% at full strength. All 9 palette locations remain bounded.
for intensity in (0.0, 0.25, 0.5, 1.0):
    boost = 1.0 + 0.06 * intensity
    assert 1.0 <= boost <= 1.06 + 1e-9
    for y in (0.0, 0.5, 1.0):
        tone = (0.5 - y) * 2 * intensity
        gamma = 1.0 - 0.10 * tone
        exposure = 0.02 * tone
        assert 0.9 <= gamma <= 1.1
        assert -0.02 <= exposure <= 0.02
        for x in (0.0, 0.5, 1.0):
            color = (x - 0.5) * 2 * intensity
            sat = 1.0 + color * (0.36 if color >= 0 else 0.24)
            assert 0.76 <= sat <= 1.36
print("PASS: original UI intact; v1.4 color axes restored + 6% colored-look saturation only")
