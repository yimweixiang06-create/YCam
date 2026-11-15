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
assert "CATransaction.setDisableActions(true)" in home
assert "DragGesture(minimumDistance: 0).onEnded" not in home
assert "DragGesture(minimumDistance: 12 * m.s" not in home
assert "camera.setMode(target)" in home
assert "withAnimation(.snappy(duration: 0.25))" not in home
# Swipe direction must match the visible left-to-right order: 视频 / 照片 / 人像.
# Rightward finger movement selects the next item; leftward selects the previous.
assert "stepMode(dx > 0 ? 1 : -1)" in home
assert "show(position: CGFloat(startingIndex) + dx / (68 * scale))" in home
assert "max(0, startingIndex + (dx > 0 ? steps : -steps)))" in home
assert "stepMode(dx > 0 ? -1 : 1)" not in home
assert "show(position: CGFloat(startingIndex) - dx / (68 * scale))" not in home
assert "max(0, startingIndex + (dx < 0 ? steps : -steps)))" not in home
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
assert "无需选择，始终请求最高分辨率" in panel
assert "recordingBadge" in home and "camera.isRecording" in home
print("PASS: max-only photos; pinch zoom; no old lighting overlay; low-latency UIKit mode bar with verified swipe directions; top controls do not resize preview")

# Motion and safe-area regressions (v1.1.7)
metrics = (root / "CameraControls.swift").read_text(encoding="utf-8")
palette_src = (root / "DotPalette.swift").read_text(encoding="utf-8")
engine = (root / "FilterEngine.swift").read_text(encoding="utf-8")
assert "rowCenterY: CGFloat { H - (max(bottomInset, 24 * s) + 44 * s) }" in metrics
assert "shutterCenterY: CGFloat { H - (max(bottomInset, 24 * s) + 128 * s) }" in metrics
assert "CATransaction.setAnimationDuration(0.17)" in home
assert "if visualIndex != nearest" in home
assert 'coordinateSpace: .named("stylePalette")' in palette_src
assert "let columns = 11" in palette_src
assert "CGFloat(col) / CGFloat(columns - 1)" in palette_src
assert "CGFloat(row) / CGFloat(rows - 1)" in palette_src
assert "pendingBuild?.cancel()" in engine and "milliseconds(32)" in engine
